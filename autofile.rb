require 'thread'
require 'fileutils'

class AutoFile
  def AutoFile.directory=(dir)
    @directory = dir
    unless File.directory? dir
      FileUtils.mkdir_p(dir)
    end
  end
  def AutoFile.directory
    if defined? @directory
      @directory
    else
      raise "AutoFile.directory not defined"
    end
  end

  PREFIX = 'af-'

  def AutoFile.clear
    GC.start
    objs = []
    ObjectSpace.each_object(AutoFile) {|obj| objs << obj }
    required_files = {}
    objs.each {|obj| required_files[obj.filename] = true }
    useless_files = []
    Dir.foreach(AutoFile.directory) {|name|
      next unless /\A#{Regexp.quote PREFIX}/o =~ name
      next if required_files[name]
      useless_files << name
    }
    useless_files.each {|name|
      File.unlink(File.join(AutoFile.directory, name))
    }
  end

  def initialize(filename_hint='', initial_content='', content_type=nil)
    dir = AutoFile.directory
    generate_filename_candidates(filename_hint, initial_content, content_type) {|cand|
      cand.gsub!(/--+/, '-')
      filename = File.join(dir, cand)
      begin
        file = File.open(filename, File::RDWR|File::CREAT|File::EXCL)
        file << initial_content
        file.close
        @filename = cand
        break
      rescue Errno::EEXIST
        next
      end
    }
  end
  attr_reader :filename

  def content
    File.read(File.join(AutoFile.directory, @filename))
  end

  ExtSynonym = {
    '.html' => ['.htm']
  }
  ExtSynonym.default = []

  def generate_filename_candidates(filename_hint, initial_content, content_type)
    base = nil
    ext = nil
    if %r{\A(http|ftp):/*} =~ filename_hint
      filename_hint = $'
      filename_hint = $` if /[?#]/ =~ filename_hint
    end

    if /\A\x1f\x8b/ !~ initial_content && /\.gz\z/ =~ filename_hint
      filename_hint = $`
    end

    if content_type == 'text/html'
      ext = '.html'
    elsif /\.[a-z0-9]{1,5}\z/ =~ filename_hint
      ext = $&
    elsif /\ALIRS/i =~ initial_content
      ext = '.lirs'
    elsif /<html|<title|<!DOCTYPE HTML/i =~ initial_content
      ext = '.html'
    else
      ext = ''
    end

    filename_hint.delete! '^0-9A-Za-z_/.-'
    arr = filename_hint.split(%r{/+})
    arr.reject! {|elt| elt.empty? }
    case arr.length
    when 0
      base = 'autofile'
    when 1
      base = arr[0]
    else
      base = arr[0] + '-' + arr[-1]
    end
    base = $` if /#{Regexp.alt ext, *ExtSynonym[ext]}\z/i =~ base

    Thread.exclusive {
      yield "#{PREFIX}#{base}#{ext}"
      time = Time.now
      base << "-#{time.strftime('%m-%d')}"
      yield "#{PREFIX}#{base}#{ext}"
      base << "-#{time.strftime('%H:%M')}"
      yield "#{PREFIX}#{base}#{ext}"
      base << ":#{time.strftime('%S')}"
      yield "#{PREFIX}#{base}#{ext}"
      i = 1
      while true
        yield "#{PREFIX}#{base}-#{i}#{ext}"
        i += 1
      end
    }
  end
end
