#!/usr/bin/env ruby

$KCODE = 'e'

require 'tempura/template'
require 'open-uri'
require 'uri'
require 'time'
require 'yaml'
require 'mconv'
require 'timeout'
require 'net/http'
require 'pp'
require 'optparse'
require 'zlib'
require 'lirs'
require 'autofile'
require 'htree'
require 'string-util'
require 'tempfile'

CONFIG_FILENAME = 'config.yml'
STATUS_FILENAME = 'status.rm'

TEMPLATE_LATEST_FILENAME = 't.latest.html'
OUTPUT_LATEST_FILENAME = 'latest.html'
OUTPUT_LIRS_FILENAME = 'sites.lirs.gz'

AutoFile.directory = 'tmp' # xxx: should be configurable.

def Time.httpdate_robust(str)
  Time.httpdate(str) rescue Time.parse(str)
end

class Entry
  ENTRIES = {}

  def initialize(hash, config)
    @status = hash
    @config = config
    related_uris.each {|uri|
      ENTRIES[uri] ||= []
      ENTRIES[uri] << self
    }
  end
  attr_reader :status
  attr_reader :config

  def uri
    @config['URI']
  end

  def related_uris
    result = []
    result << @config['URI']
    result << @config['LinkURI'] if @config['LinkURI']
    result.concat @config['RelatedURI'].split(/\s+/) if @config['RelatedURI']
    if logseq = @status['_log']
      logseq.each {|log|
        result << log['baseURI'] if log['baseURI']
        result << log['extractedLinkURI'] if log['extractedLinkURI']
      }
    end
    result.uniq!
    result
  end

  def update_info?
    @config.include? 'UpdateInfo'
  end

  def should_check?
    ARGV.empty? or
    @status['_update_info'] or
    !(related_uris & ARGV).empty?
  end

  DefaultMinimumInterval = 5 * 60
  DefaultMaximumInterval = 24 * 60 * 60
  def timing_check
    t1 = next_timing
    t2 = Time.now
    t1 <= t2
  end

  def expect_next_by_periodical
    h = find_last_200
    return nil unless h
    periodical = h['lastModifiedSequence'] || h['periodical']
    return nil unless periodical 
    return nil if periodical.length < 2
    last_modified = periodical.last
    intervals = []
    prev = nil
    periodical.each {|curr|
      intervals << curr - prev if prev && prev < curr
      prev = curr
    }
    t = last_modified + intervals.min
    begin # adjust server/client time difference
      t += (h['clientDateEnd'] || h['clientDateBeg']) - Time.httpdate_robust(h['serverDateString'])
    rescue
    end
    t
  end

  def next_timing
    if @status['_update_info']
      Time.now
    elsif e1 = find_first_error
      min = @config.fetch('MinimumInterval', DefaultMinimumInterval) # xxx: should support units other than second.
      e2 = find_last_error
      e1t = e1['clientDateEnd']
      e2t = e2['clientDateEnd']
      if e1.equal? e2
        e1t + min
      else
        e2t + (e2t - e1t)
      end
    elsif s1 = find_first_200_with_current_content # Is there any 200?
      min = @config.fetch('MinimumInterval', DefaultMinimumInterval) # xxx: should support units other than second.
      max = @config.fetch('MaximumInterval', DefaultMaximumInterval)
      min = max if max < min

      s2 = find_last_success
      s2t = s2['clientDateEnd'] || s2['clientDateBeg']

      if @config['Periodical']
        s1t = expect_next_by_periodical
        return s1t if s1t && s2t < s1t
      end
      if !s1t
        begin
          s1t = Time.httpdate_robust(s1['lastModifiedString']) +
            ((s1['clientDateEnd'] || s1['clientDateBeg']) - Time.httpdate_robust(s1['serverDateString']))
        rescue
          s1t = s1['clientDateEnd'] || s1['clientDateBeg']
        end
        s1t = s2t if s2t < s1t
      end

      r = s2t + (s2t - s1t)
      if r < s2t + min
        s2t + min
      elsif s2t + max < r
        s2t + max
      else
        r
      end
    else
      Time.now
    end
  end

  def check
    uri = @config['URI']
    @status['_log'] = [] unless @status['_log']
    logseq = @status['_log']

    log = @config.dup

    log['clientDateBeg'] = client_date_1 = Time.now
    STDERR.puts "#{client_date_1.iso8601} fetch start #{uri}" if $VERBOSE
    page, meta = fetch(log)
    log['clientDateEnd'] = client_date_2 = Time.now
    if $VERBOSE
      if log['trouble']
        STDERR.puts "#{client_date_2.iso8601} fetch end ERROR: #{log['trouble']} #{uri}"
        if log['backtrace']
          STDERR.puts "|#{client_date_2.iso8601} ERROR: #{log['trouble']} (#{log['exception_class']}) #{uri}"
          log['backtrace'].each {|pos| STDERR.puts "| #{pos}" }
        end
      else
        STDERR.puts "#{client_date_2.iso8601} fetch end #{log['status']} #{log['statusMessage']} #{uri}"
      end

    end

    begin
      examine(page, meta, log) if page
    rescue
      STDERR.puts "|#{Time.now.iso8601} examine ERROR: #{$!.message} (#{$!.class}) #{uri}"
      $!.backtrace.each {|pos| STDERR.puts "| #{pos}" }
      raise
    end

    add_log(log)
    @status.delete '_update_info'
  end

  def fetch(log)
    uri = @config['URI']
    opts = {
      "Accept-Encoding"=>"gzip, deflate",
      "User-Agent" => @config.fetch('UserAgent', 'samidare')
    }
    if h = find_last_200 and @status['_log'].last['status'] != '412'
      # DJB's publicfile rejects requests which have If-None-Match as:
      #   412 I do not accept If-None-Match
      # Since 412 means `Precondition Failed', samidare tries request without
      # precondition.  If it success, samidare may know new valid condition.
      # For example apache is replaced with publicfile,
      # ETag should be forgotten.  Above 412 handling handle this case.
      if @config.fetch('UseIfModifiedSince', true)
        opts['If-Modified-Since'] = h['lastModifiedString'] if h['lastModifiedString']
      end
      opts['If-None-Match'] = h['eTag'] if h['eTag']
    end
    #PP.pp([uri, opts], STDERR) if $VERBOSE
    page = nil
    meta = nil
    status = nil
    status_message = nil
    exception_class = nil
    trouble = nil
    backtrace = nil
    begin
      page = timeout(@config['Timeout'] || 200) { URI.parse(uri).read(opts) }
      meta = page.meta
      status = page.status[0]
      status_message = page.status[1]
    rescue OpenURI::HTTPError
      if $!.io.status.first == '304'
        meta = $!.io.meta
        status = $!.io.status[0]
        status_message = $!.io.status[1]
      else
        meta = $!.io.meta
        status = $!.io.status[0]
        status_message = $!.io.status[1]
        trouble = "#{status} #{status_message}"
        exception_class = $!.class.name
      end
    rescue StandardError, TimeoutError
      trouble = $!.message
      backtrace = $!.backtrace unless TimeoutError === $!
      exception_class = $!.class.name
    end

    log['status'] = status
    log['statusMessage'] = status_message if status_message
    log['serverDateString'] = meta['date'] if meta && meta['date']
    log['trouble'] = trouble if trouble
    log['backtrace'] = backtrace if backtrace
    log['exception_class'] = exception_class if exception_class

    if @config['LogMeta']
      log['logSendHeader'] = opts
      log['logRecvHeader'] = meta
    end

    return page, meta
  end

  def examine(page, meta, log)
    uri = @config['URI']
    log['baseURI'] = page.base_uri.to_s if page.base_uri.to_s != uri
    log['lastModifiedString'] = meta['last-modified'] if meta['last-modified']
    log['eTag'] = meta['etag'] if meta['etag']
    content_type = log['contentType'] = page.content_type if page.content_type

    content, content_encoding = decode_content_encoding(page, log)
    log['content'] = AutoFile.new(uri, content, content_type)

    content_charset = @config.fetch('ForceCharset') {
      c = page.charset { nil }
      c = nil if c && !Mconv.valid_charset?(c)
      c = @config['DefaultCharset'] if !c
      c = content.guess_charset if !c && !content_encoding
      c
    }
    content_charset = content_charset.downcase
    log['contentCharset'] = content_charset if content_charset

    # checksum for gzip/deflate decoded content.
    # compression level is not affected.
    log['checksum'] = content.sum

    return if content_encoding

    decoded_content = content.decode_charset(content_charset) if content_charset

    examine_html(content_type, decoded_content, log)
    examine_lirs(decoded_content, log)

    case @config['UpdateInfo']
    when 'lirs'
      check_lirs(content)
    when 'html'
      check_html(log)
    end
  end

  def examine_html(content_type, decoded_content, log)
    if %r{\A(?:text/html|text/xml|application/(?:[A-Za-z0-9.-]+\+)?xml)\z} !~ content_type &&
      /\A<\?xml/ !~ decoded_content
      return
    end

    t = HTree.parse(decoded_content)

    title = t.title
    log['extractedTitle'] = title if title

    author = t.author
    log['extractedAuthor'] = author if author

    t.traverse_element("meta") {|e|
      begin
        next unless e.fetch_attr("http-equiv").downcase == "last-modified"
        log['extractedLastModified'] = Time.httpdate_robust(e.fetch_attr("content"))
        break
      rescue IndexError, ArgumentError
      end
    }

    root = t.root rescue nil
    if root and root.name == 'rss' || root.name == '{http://www.w3.org/1999/02/22-rdf-syntax-ns#}RDF'
      if link = t.find_element('link')
        link_uri = link.extract_text.to_s.strip
        if %r{\Ahttp://} =~ link_uri
          log['extractedLinkURI'] = link_uri
        end
      end
    end

    t, checksum_filter = ignore_tree(t)
    log['checksum_filter'] = checksum_filter unless checksum_filter.empty?
    log['checksum_filtered'] = t.extract_text.rcdata.sum
  end

  def ignore_tree(tree, config=@config)
    if ignore_path = config['IgnorePath']
      ignore_path = ignore_path.split(/\s+/)
    else
      ignore_path = []
    end
    ignore_pattern = path2pattern(*ignore_path)

    if ignore_class = config['IgnoreClass']
      ignore_class = ignore_class.split(/\s+/)
    else
      ignore_class = []
    end

    if ignore_id = config['IgnoreID']
      ignore_id = ignore_id.split(/\s+/)
    else
      ignore_id = []
    end

    t = tree.filter_with_path {|e, path|
      not (
        (HTree::Elem === e && (e.name == 'style' ||
                               e.name == 'script')) ||
        ignore_pattern =~ path ||
        (HTree::Elem === e && (ignore_class.include?(e.get_attr('class')) ||
                               ignore_id.include?(e.get_attr('id'))))
      )
    }

    # xxx: checksum_filter format should be changed.
    checksum_filter = []
    checksum_filter.concat ['IgnorePath', *ignore_path] if !ignore_path.empty?
    checksum_filter.concat ['IgnoreClass', *ignore_class] if !ignore_class.empty?
    checksum_filter.concat ['IgnoreID', *ignore_id] if !ignore_id.empty?

    [t, checksum_filter]
  end

  def examine_lirs(decoded_content, log)
    uri = URI.parse(@config['URI'])
    return if %r{\.lirs(?:.gz)?\z} !~ uri.path
    return if log['extractedTitle'] && log['extractedAuthor']

    lirs = LIRS.decode(decoded_content)

    if $VERBOSE
      lirs.each {|record|
        now = Time.now
        if record.last_modified != '0' &&
           record.last_detected != '0' &&
           record.last_modified.to_i > record.last_detected.to_i
          STDERR.puts "#{now.iso8601} info: strange LIRS: Last-Modified/Detected inversion: #{record.last_modified.to_i - record.last_detected.to_i}sec #{uri} #{record.encode.inspect}"
        end
        if record.last_modified != '0' && record.last_modified.to_i > now.to_i
          STDERR.puts "#{now.iso8601} info: strange LIRS: future Last-Modified: #{record.last_modified.to_i - now.to_i}sec #{uri} #{record.encode.inspect}"
        end
      }
    end

    return if lirs.size != 1
    
    lirs.each {|record|
      target_uri = URI.parse(record.target_url)
      return if target_uri.scheme != uri.scheme
      return if target_uri.host.downcase != uri.host.downcase
      log['extractedLinkURI'] = record.target_url unless log['extractedLinkURI']
      log['extractedTitle'] = record.target_title unless log['extractedTitle']
      log['extractedAuthor'] = record.target_maintainer unless log['extractedAuthor']
      log['extractedLinkURI'] = record.target_url unless log['extractedLinkURI']
    }
  rescue LIRS::Error
    # ignore invalid lirs file.
    STDERR.puts "#{Time.now.iso8601} LIRS Error: #{uri}" if $VERBOSE
  end

  def path2pattern(*paths)
    /\A#{Regexp.union(*paths.map {|path|
      Regexp.new(path.gsub(%r{[^/]+}) {|step|
        if /\[(\d+)\]\z/ =~ step
          n = $1.to_i
          if $1.to_i == 1
            Regexp.quote($`) + "(?:\\[#{n}\\])?"
          else
            Regexp.quote(step)
          end
        else
          Regexp.quote(step) + '(\[\d+\])?'
        end
      }.gsub(%r{//+}) {
        "/(?:[^/]+/)*"
      })
    })}\z/
  end

  def decode_content_encoding(page, log)
    content = page
    if page.content_encoding.empty?
      if /\A\x1f\x8b/ =~ content # gziped?
        begin
          content = content.decode_gzip
        rescue Zlib::Error
        end
      end
    else
      content_encoding = page.content_encoding.dup
      while !content_encoding.empty?
        case content_encoding.last
        when 'gzip', 'x-gzip'
          begin
            content = content.decode_gzip
          rescue Zlib::Error
            break
          end
        when 'deflate'
          content = content.decode_deflate
        else
          break
        end
        content_encoding.pop
      end
      content_encoding = nil if content_encoding.empty?
      log['contentEncoding'] = content_encoding if content_encoding
    end
    return content, content_encoding
  end

  def check_lirs(new_lirs)
    logseq = @status['_log']
    old_lirs = nil
    logseq.reverse_each {|h|
      if h['content']
        begin
          old_lirs = h['content'].content
          break
        rescue Errno::ENOENT
        end
      end
    }
    begin
      l1 = LIRS.decode(old_lirs) if old_lirs
      l2 = LIRS.decode(new_lirs)
      count_all = 0
      count_interest = 0
      count_update = 0
      l2.each {|r2|
        count_all += 1
        uri = r2.target_url
        if es = ENTRIES[uri]
          es.each {|e|
            count_interest += 1
            if !old_lirs or (r1 = l1[uri] and r1.last_modified != r2.last_modified)
              t1 = Time.at(r1.last_modified.to_i) if old_lirs
              t2 = Time.at(r2.last_modified.to_i)
              last_success = e.find_last_success
              if last_success && last_success['clientDateEnd'] < t2 #xxx: not so acculate.
                count_update += 1
                p [:LIRS_UPDATE, uri, t1, t2, @config['URI']]
                e.status['_update_info'] = true
              end
            end
          }
        end
      }
      STDERR.puts "LIRS total: #{count_update} / #{count_interest} / #{count_all} - #{@config['URI']}" if $VERBOSE
    rescue
      # External update information is a just hint.
      # So it is ignorable even if it has some trouble.
      STDERR.puts "check_lirs: error on #{@config['URI']}: #$!"
      #pp $!.backtrace
    end
  end

  def extract_html_update_info_rec(elt, result, base_uri_cell)
    hrefs = []

    if HTree::Elem === elt && %r[\A(?:\{http://www.w3.org/1999/xhtml\})?base\z] =~ elt.name
      if href = elt.get_attr('href')
        base_uri_cell[0] = URI.parse(href)
      end
    elsif HTree::Elem === elt && %r[\A(?:\{http://www.w3.org/1999/xhtml\})?a\z] =~ elt.name
      if href = elt.get_attr('href')
        href = (base_uri_cell[0] + URI.parse(href)).to_s
        hrefs << href if ENTRIES[href]
      end
    else
      elt.children.each {|e|
        next unless HTree::Elem === e
        hrefs.concat extract_html_update_info_rec(e, result, base_uri_cell)
      }
    end

    hrefs.uniq!

    if HTree::Elem === elt && elt.name == @config.fetch('UpdateElement', 'a')
      hrefs.each {|uri|
        result[uri] ||= []
        result[uri] << elt
      }
      return []
    else
      return hrefs
    end
  end

  def extract_html_update_info(log)
    return {} unless log && log['content'] && log['contentCharset']
    content = log['content'].content
    content = content.decode_charset(log['contentCharset'])
    tree = HTree.parse(content)
    tree, checksum_filter = ignore_tree(tree, log)
    base_uri = URI.parse(log['baseURI'] || log['URI'])
    extract_html_update_info_rec(tree, info={}, [base_uri])
    info
  end

  def compare_html_update_info(old_log, new_log)
    count_update = 0
    count_interest = 0

    old_info = extract_html_update_info(old_log)
    new_info = extract_html_update_info(new_log)

    (old_info.keys & new_info.keys).each {|uri|
      count_interest += 1
      old_str = old_info[uri].map {|elt| elt.extract_text }.join
      new_str = new_info[uri].map {|elt| elt.extract_text }.join
      if old_str != new_str
        #pp [uri, old_info[uri]]
        #pp [uri, new_info[uri]]
        count_update += 1
        p [:HTML_UPDATE, uri, old_str, new_str, @config['URI']]
        yield uri
      end
    }

    STDERR.puts "HTML total: #{count_update} / #{count_interest} - #{@config['URI']}" if $VERBOSE
  end

  def check_html(new_log=nil)
    begin
      if new_log
        old_log = find_last_200
      else
        new_log = find_last_200
        old_log = find_last_200_with_previous_content
      end
      compare_html_update_info(old_log, new_log) {|uri|
        ENTRIES[uri].each {|e|
          e.status['_update_info'] = true
        }
      }
    rescue
      # External update information is a just hint.
      # So it is ignorable even if it has some trouble.
      STDERR.puts "check_html error on #{@config['URI']}: #$!"
    end
  end

  StatusMap = {
    '200' => 's', # Success
    '304' => 'n', # Not-Modified
  }
  StatusMap.default = 'e' # Error

  MaxPeriodicalNum = 30
  def add_periodical_info(h)
    return if h['status'] != '200'

    logseq = @status['_log']

    periodical = nil
    logseq.reverse_each {|l|
      if l['lastModifiedSequence']
        periodical = l['lastModifiedSequence'].dup
        break
      elsif l['periodical']
        periodical = l['periodical'].dup
        break
      end
    }
    periodical ||= []

    begin
      t = Time.httpdate_robust(h['lastModifiedString'])
    rescue
    end

    if t && (periodical.empty? || periodical.last != t)
      periodical << t
    end

    if MaxPeriodicalNum < periodical.length
      periodical = periodical[(-MaxPeriodicalNum)..(-1)]
    end

    h['lastModifiedSequence'] = periodical if !periodical.empty?
  end

  def content_unchanged(log1, log2)
    return true if log1['checksum'] &&
                   log2['checksum'] &&
                   log1['checksum'] == log2['checksum']
    return true if log1['checksum_filtered'] &&
                   log2['checksum_filtered'] &&
                   log1['checksum_filter'] == log2['checksum_filter'] &&
                   log1['checksum_filtered'] == log2['checksum_filtered']
    false
  end

  def add_log(log)
    @status['_log'] = [] unless @status['_log']

    #add_periodical_info(log) if @config['Periodical']
    add_periodical_info(log)

    logseq = @status['_log']

    case StatusMap[log['status']]
    when 'e'
      history = logseq.map {|l| StatusMap[l['status']] }.join + ' ' + StatusMap[log['status']]
      if /ee e/ =~ history
        logseq.pop
      end
      logseq << log
    when 's', 'n'
      logseq.reject! {|l| StatusMap[l['status']] == 'e' }
      logseq.shift while !logseq.empty? && StatusMap[logseq.first['status']] == 'n'

      logseq << log

      #pp logseq.map {|l| StatusMap[l['status']] + "#{l['checksum']}" }
      logs = [[]]
      logseq.each {|l|
        if logs.last.empty?
          logs.last << l
        elsif StatusMap[l['status']] == 'n'
          logs.last << l
        elsif content_unchanged(logs.last.last, l)
          logs.last << l
        else
          logs << [l]
        end
      }
      #pp logs.map {|ll| ll.map {|l| StatusMap[l['status']] + "#{l['checksum']}" } }

      logs[0...-1].each {|ll|
        ll.reject! {|l| StatusMap[l['status']] == 'n' }
        ll[1..-1] = [] if 2 <= ll.length
      }

      ll = logs.last
      ll.reject! {|l| StatusMap[l['status']] == 'n' } # removes `log' if it is 'n'.
      ll[1...-1] = [] if 2 < ll.length 
      if StatusMap[log['status']] == 'n'
        ll << log # re-add `log'.
      end

      num_discards = 0

      nlogs = @config.fetch('NumLogs', 2)
      #pp logs.map {|ll| ll.map {|l| StatusMap[l['status']] + "#{l['checksum']}" } }
      if nlogs < logs.length
        num_discards = logs.length - nlogs
      end
      #pp logs.map {|ll| ll.map {|l| StatusMap[l['status']] + "#{l['checksum']}" } }

      if log_expire = @config['LogExpire']
        log_expire = parse_time_suffix(log_expire) || 0 if String === log_expire
        limit = Time.now - log_expire
        while 0 < num_discards && limit < logs[num_discards-1][0]['clientDateBeg']
          num_discards -= 1
        end
      end

      logs[0, num_discards] = []

      logseq.replace logs.flatten
    else
      raise "unrecognized log-status [bug]: #{StatusMap[log['status']].inspect}"
    end

    unless logseq.last.equal? log
      raise "current log is not added [bug]"
    end
  end

  def parse_time_suffix(str)
    case str
    when /\A(\d+)(s|sec|second)?\z/
      $1.to_i
    when /\A(\d+)(m|min|minute)\z/
      $1.to_i * 60
    when /\A(\d+)(h|hour)\z/
      $1.to_i * 60 * 60
    when /\A(\d+)(d|day)\z/
      $1.to_i * 60 * 60 * 24
    else
      nil
    end
  end

  def find_last_200_with_previous_content
    current = nil
    @status['_log'].reverse_each {|log|
      next unless log['status'] == '200'
      if !current
        current = log
      elsif !content_unchanged(current, log)
        return log
      end
    }
    nil
  end

  def find_first_200_with_current_content
    result = nil
    @status['_log'].reverse_each {|h|
      if h['status'] == '200'
        if !result
          result = h
        elsif !content_unchanged(result, h)
          return result
        else
          result = h
        end
      end
    }
    result
  end

  def find_last_200
    @status['_log'].reverse_each {|h|
      return h if h['status'] == '200'
    }
    nil
  end

  def find_last_success # 200 or 304
    @status['_log'].reverse_each {|h|
      return h if StatusMap[h['status']] != 'e'
    }
    nil
  end

  def find_first_error
    @status['_log'].each {|h|
      return h if StatusMap[h['status']] == 'e'
    }
    nil
  end

  def find_last_error
    @status['_log'].reverse_each {|h|
      return h if StatusMap[h['status']] == 'e'
    }
    nil
  end

  def presentation_data
    h = @config.dup
    logseq = @status['_log']
    h.update @status # xxx
    h['title'] = h['Title']
    h['author'] = h['Author']
    h['last-modified'] = nil
    h['info'] = ''
    h['linkURI'] = h['LinkURI']
    unless logseq.empty?
      if l = find_first_200_with_current_content
        h['last-modified-found'] = l['clientDateBeg'] # xxx: clientDateEnd is better?
        if l.include? 'lastModifiedString'
          h['last-modified'] = Time.httpdate_robust(l['lastModifiedString']).localtime
          l2 = find_last_200
          unless l.equal? l2
            if l['lastModifiedString'] != l2['lastModifiedString']
              h['info'] << '[Touch]'
            else
              h['info'] << '[NoIMS]'
            end
          end
        elsif l.include? 'extractedLastModified'
          h['last-modified'] = l['extractedLastModified'].getlocal
        else
          h['last-modified'] = l['clientDateBeg'].getlocal
          h['info'] << '[NoLM]'
        end
        if l.include? 'baseURI'
          h['info'] << '[Redirect]'
        end
        h['title'] ||= l['extractedTitle'] if l['extractedTitle']
        h['author'] ||= l['extractedAuthor'] if l['extractedAuthor']
        h['linkURI'] ||= l['extractedLinkURI'] if l['extractedLinkURI']
      end
      if StatusMap[logseq.last['status']] == 'e'
        l = logseq.last
        if l['status']
          if l['statusMessage']
            h['info'] << "[#{l['status']} #{l['statusMessage']}]"
          else
            h['info'] = "[#{l['status']}]"
          end
        elsif l['trouble']
          h['info'] = "[#{l['trouble']}]"
        else
          h['info'] = '[no status]'
        end
      end
    end
    h['title'] ||= h['LinkURI'] if h['LinkURI']
    h['title'] ||= h['URI']
    h['linkURI'] ||= h['URI']

    h
  end

  def merge(hash)
    @status = hash.dup.update(@status)
  end

  def recent_log2
    if logseq = @status['_log']
      log1 = log2 = nil
      logseq.reverse_each {|log|
        next unless log['content']
        if log2 == nil
          log2 = log
        else
          log1 = log
          break unless content_unchanged(log1, log2)
        end
      }
      [log1, log2]
    end
  end

  def dump_filenames2
    log1, log2 = recent_log2
    puts log1['content'].pathname if log1
    puts log2['content'].pathname if log2
  end

  def diff_content
    log1, log2 = recent_log2
    return unless log1 && log2
    filename1 = log1['content'].pathname
    filename2 = log2['content'].pathname
    tree1, checksum_filter1 = ignore_tree(HTree.parse(File.read(filename1).decode_charset_guess), log1)
    tree2, checksum_filter2 = ignore_tree(HTree.parse(File.read(filename2).decode_charset_guess), log2)

    text1 = []
    tree1.traverse_with_path {|n, path|
      text1 << [n.to_s, path] if HTree::Text === n
    }

    text2 = []
    tree2.traverse_with_path {|n, path|
      text2 << [n.to_s, path] if HTree::Text === n
    }

    puts "checksum1: #{tree1.extract_text.to_s.sum} #{checksum_filter1.inspect} #{filename1}"
    puts "checksum2: #{tree2.extract_text.to_s.sum} #{checksum_filter2.inspect} #{filename2}"

    [text1.length, text2.length].min.times {
      t1, p1 = text1.last
      t2, p2 = text2.last
      t1 = t1.gsub(/\s+/, '') if t1
      t2 = t2.gsub(/\s+/, '') if t2
      if t1 == t2
        text1.pop
        text2.pop
      else
        break
      end
    }

    num = 10
    0.upto([text1.length, text2.length].max - 1) {|i|
      t1, p1 = text1[i]
      t2, p2 = text2[i]
      t1 = t1.gsub(/\s+/, '') if t1
      t2 = t2.gsub(/\s+/, '') if t2
      if t1 != t2
        pp [text1[i], text2[i]]
        num -= 1
        if num == 0
          puts "..."
          break
        end
      end
    }

    tf1 = Tempfile.new('htmldiff1')
    PP.pp(tree1, tf1)
    tf1.close

    tf2 = Tempfile.new('htmldiff2')
    PP.pp(tree2, tf2)
    tf2.close

    system("diff -u #{tf1.path} #{tf2.path}")
  end
end

module Enumerable
  $opt_max_threads = 8
  def concurrent_map(max_threads=$opt_max_threads, &block)
    arr = self.to_a.dup
    if max_threads == 1 || arr.length == 1
      self.map(&block)
    else
      queue = (0...arr.length).to_a

      max_threads = arr.length if arr.length < max_threads

      threads = []
      max_threads.times {
        threads << Thread.new {
          while i = queue.shift
            arr[i] = yield arr[i]
          end
        }
      }

      threads.each {|t| t.join }
      arr
    end
  end
end

# Use dobule quote to quote attributes.
# This makes decoding &apos; safe.
# [ruby-talk:74223]
class REXML::Attribute
  def to_string
    %Q<#@expanded_name="#{to_s().gsub(/"/, '&quot;')}">
  end
end

class Samidare
  def open_lock(filename, nonblock=false)
    dirname = File.dirname filename
    basename = File.basename filename
    tmpname = "#{dirname}/.,#{basename},#$$"

    1.times {
      begin
        target = File.open(filename, File::RDWR|File::CREAT)
        stat1 = target.stat
        if nonblock
          unless target.flock(File::LOCK_EX | File::LOCK_NB)
            STDERR.puts "fail to lock: #{filename}"
            return
          end
        else
          target.flock(File::LOCK_EX)
        end
        stat2 = File.stat(filename)
        redo if stat1.ino != stat2.ino

        begin
          File.open(tmpname, 'w') {|tmp|
            yield target, tmp
          }
          stat2 = File.stat(filename) # manually unlocked?
          File.rename(tmpname, filename) if stat1.ino == stat2.ino
        ensure
          File.unlink tmpname if FileTest.exist? tmpname
        end
      ensure
        target.close if target
      end
    }
  end

  def config_flatten(arr, default={})
    result = []
    arr.each {|elt|
      case elt
      when Hash
        if elt.include? 'URI'
          result << default.dup.update(elt)
        else
          default = default.dup.update(elt)
        end
      when Array
        result.concat config_flatten(elt, default)
      when String
        result << default.dup.update({'URI'=>elt})
      end
    }
    result
  end

  def deep_copy(o)
    Marshal.load(Marshal.dump(o))
  end

  def deep_freeze(o)
    objs = []
    o = Marshal.load(Marshal.dump(o), lambda {|obj| objs << obj })
    objs.each {|obj| obj.freeze }
    o
  end

  def load_config
    @configuration = {}
    config = config_flatten(File.open(CONFIG_FILENAME) {|f| YAML.load(f) })
    config.each_with_index {|h, i|
      h.reject! {|k, v| /\A[A-Z]/ !~ k }
      uri = h['URI']
      if @configuration.include? uri
        @configuration[uri].update h
        config[i] = nil
      else
        @configuration[uri] = h
      end
    }
    config.compact!
    config
  end

  #def load_status(f) YAML.load(f) end
  #def save_status(f, d) f.puts d.to_yaml end
  def load_status(f) Marshal.load(f) end
  def save_status(d, f) Marshal.dump(d, f) end

  def open_status(readonly=false)
    if readonly
      open(STATUS_FILENAME) {|f|
        if f.stat.size == 0
          status = []
        else
          status = load_status(f)
        end
        status = deep_freeze(status)
        yield status
      }
    else
      open_lock(STATUS_FILENAME, true) {|f, out|
        if f.stat.size == 0
          status = []
        else
          status = load_status(f)
          AutoFile.clear
        end
        yield status
        save_status(status, out)
      }
    end
  end

  def output_file(filename, content)
    dir = File.dirname filename
    if FileTest.writable? dir
      filename_new = filename + '.new'
      open(filename_new, 'w') {|f|
        f.print content
      }
      File.rename filename_new, filename
    else
      open(filename, 'w') {|f|
        f.print content
      }
    end
  end

  module CharConvInternal
    module_function
    def to_u8(str) str.encode_charset('utf-8') end
    def from_u8(str) str.decode_charset('utf-8') end
  end

  def generate_output(data)
    result = Tempura::Template.new_with_string(File.read(@opt_template).decode_charset_guess, CharConvInternal).expand(data)
    result.gsub!(/&apos;/, "'") # Don't use &apos; because HTML4.01 has no such entity.
    result << "\n" if /\n\z/ !~ result
    if @opt_output != '-'
      output_file(@opt_output, result)
      output_file(@opt_output + '.gz', result.encode_gzip)
    else
      puts result
    end
  end

  def generate_lirs(data)
    str = ''
    data["antenna"].each {|h|
      next unless h['last-modified'] && h['last-modified-found']
      #p ['LIRS', h['last-modified'], h['last-modified-found'], h['URI'], h['title'], h['author']]
      str << 'LIRS,'
      str << h['last-modified'].to_i.to_s << ','
      str << h['last-modified-found'].to_i.to_s << ','
      str << '32400,'
      str << '0,'
      str << h['linkURI'].gsub(/[,\\]/) { "\\#$&" } << ','
      str << h['title'].gsub(/[,\\]/) { "\\#$&" }.strip.gsub(/\s/, ' ') << ','
      str << (h['author'] || '0').gsub(/[,\\]/) { "\\#$&" }.strip.gsub(/\s/, ' ') << ','
      str << '0,'
      str << "\n"
    }
    str = str.encode_charset('euc-jp')
    str = str.encode_gzip

    output_file(@opt_output_lirs, str)
  end

  def parse_options
    @opt_output = OUTPUT_LATEST_FILENAME
    @opt_output_lirs = OUTPUT_LIRS_FILENAME
    @opt_dont_check = nil
    @opt_force_check = nil
    @opt_timing = nil
    @opt_dump_config = nil
    @opt_dump_status = nil
    @opt_dump_template_data = nil
    @opt_template = TEMPLATE_LATEST_FILENAME
    @opt_remove_entry = nil
    @opt_dump_filenames = nil
    @opt_dump_filenames2 = nil
    @opt_diff_content = nil
    ARGV.options {|q|
      q.banner = 'webpecker [opts]'
      q.def_option('--help', 'show this message') {puts q; exit(0)}
      q.def_option('--verbose', '-v', 'verbose') { $VERBOSE = true }
      q.def_option('--no-check', '-n', 'don\'t check web') { @opt_dont_check = true }
      q.def_option('--force', '-f', 'force check (avoid timing control mechanism)') { @opt_force_check = true }
      q.def_option('--output=filename', '-o', 'specify output file') {|filename| @opt_output = filename }
      q.def_option('--output-lirs=filename', '-o', 'specify output file') {|filename| @opt_output_lirs = filename }
      q.def_option('--template=filename', '-T', 'specify template') {|filename| @opt_template = filename }
      q.def_option('--timing', '-t', 'show timings') { @opt_timing = true }
      q.def_option('--dump-config', 'dump flatten configuration') { @opt_dump_config = true }
      q.def_option('--dump-status', 'dump status') { @opt_dump_status = true }
      q.def_option('--dump-template-data', 'dump data for expand template') { @opt_dump_template_data = true }
      q.def_option('--dump-filenames', 'dump filenames of specified entry') { @opt_dump_filenames = true }
      q.def_option('--dump-filenames2', 'dump two recent filenames') { @opt_dump_filenames2 = true }
      q.def_option('--remove-entry', 'remove entry') { @opt_remove_entry = true }
      q.def_option('--single-thread', 'disable multi-threading') { $opt_max_threads = 1 }
      q.def_option('--diff-content', 'show difference') { @opt_diff_content = true }
      q.parse!
    }
    require 'resolv-replace' if $opt_max_threads != 1
  end

  def dump_status(status, entries)
    if ARGV.empty?
      status.each {|ent|
        pp ent
      }
    else
      entries.each {|ent|
        unless (ARGV & ent.related_uris).empty?
          pp ent.status
          puts "next time: #{ent.next_timing.localtime}"
        end
      }
    end
  end

  def dump_filenames(entries)
    entries.each {|ent|
      unless (ARGV & ent.related_uris).empty?
        if logseq = ent.status['_log']
          logseq.each {|log|
            if content = log['content']
              puts content.pathname
            end
          }
        end
      end
    }
  end

  def dump_filenames2(entries)
    entries.each {|ent|
      unless (ARGV & ent.related_uris).empty?
        ent.dump_filenames2
      end
    }
  end

  def diff_content(entries)
    entries.each {|ent|
      unless (ARGV & ent.related_uris).empty?
        ent.diff_content
      end
    }
  end

  def create_entries(config, status, readonly=false)
    logs = {}
    status.each {|status_ent|
      if status_ent.include?('URI') && status_ent.include?('_log')
        logs[status_ent['URI']] = status_ent['_log']
      end
    }

    status.clear unless readonly

    entries = []
    config.each {|config_ent|
      uri = config_ent['URI']
      logseq = logs[uri] || []
      status_ent = { 'URI' => uri, '_log' => logseq }
      status << status_ent unless readonly
      entries << Entry.new(status_ent, config_ent)
    }
    entries
  end

  def main
    parse_options
    config = load_config
    if @opt_dump_config
      puts config.to_yaml
      return
    end
    data = nil
    readonly =
      @opt_timing ||
      @opt_dont_check ||
      @opt_dump_status ||
      @opt_dump_template_data ||
      @opt_dump_filenames ||
      @opt_dump_filenames2 ||
      @opt_diff_content
    open_status(readonly) {|status|
      entries = create_entries(config, status, readonly)
      if @opt_dump_status
        dump_status(status, entries)
      elsif @opt_dump_filenames
        dump_filenames(entries)
      elsif @opt_dump_filenames2
        dump_filenames2(entries)
      elsif @opt_diff_content
        diff_content(entries)
      elsif @opt_timing
        entries = entries.map {|entry|
          [entry.next_timing.localtime, entry]
        }.sort
        now = Time.now
        entries.each {|timing, entry|
          if now && timing > now
            puts "#{now}  --- now ---"
            now = nil
          end
          h = entry.presentation_data
          s = "#{timing}: #{h['title']}"
          s << " (#{h['Author']})" if h['Author']
          puts s
        }
	if now
	  puts "#{now}  --- now ---"
	end
      elsif @opt_remove_entry
        removing_uris = {}
        entries.each {|e|
          unless (e.related_uris & ARGV).empty? || e.status['_log'].empty?
            removing_uris[e.uri] = true
          end
        }
        status.reject! {|log|
          uri = log['URI']
          if removing_uris[uri]
            STDERR.puts "removed: #{uri}" if $VERBOSE
            true
          else
            false
          end
        }
      else
        unless readonly
          update_info_entries, non_update_info_entries = entries.partition {|e| e.update_info? }
          update_info_entries.concurrent_map {|entry|
            next unless entry.update_info?
            entry.check if entry.should_check? && (@opt_force_check || entry.timing_check)
          }
          non_update_info_entries.concurrent_map {|entry|
            next if entry.update_info?
            entry.check if entry.should_check? && (@opt_force_check || entry.timing_check)
          }
        end
        update_infos, entries = entries.partition {|entry| entry.update_info? }
        data = {
          "antenna" =>
          entries.map {|entry| entry.presentation_data }.sort_by {|h|
            # [h['last-modified'], h['title']]
            if h['last-modified-found']
              [2, h['last-modified-found'], h['last-modified'], h['title']]
            elsif h['last-modified']
              [1, h['last-modified'], h['title']]
            else
              [0, h['title']]
            end
          }.reverse,
          "update_info" =>
          update_infos.map {|update_info| update_info.presentation_data }.sort_by {|h|
            # [h['last-modified'], h['title']]
            if h['last-modified-found']
              [2, h['last-modified-found'], h['last-modified'], h['title']]
            elsif h['last-modified']
              [1, h['last-modified'], h['title']]
            else
              [0, h['title']]
            end
          }.reverse
        }
        if @opt_dump_template_data
          pp data
          return
        end
        generate_output(data)
        generate_lirs(data)
      end
    }
    #PP.pp(data, STDERR) if $VERBOSE
  end

end

class Hash
  def pretty_print(pp)
    pp.group(1, '{', '}') {
      keys = self.keys
      keys.sort! if keys.all? {|k| String === k }
      keys.each {|k|
        v = self[k]
        pp.comma_breakable unless pp.first?
        pp.group {
          pp.pp k
          pp.text '=>'
          pp.group(1) {
            pp.breakable ''
            pp.pp v
          }
        }
      }
    }
  end
end


if $0 == __FILE__
  Samidare.new.main
end
