require 'zlib'

class LIRS
  RecordHeader = 'LIRS'

  def LIRS.load(filename)
    File.open (filename) {|f|
      begin
	return decode(f)
      rescue LIRS::Error
	$!.message[0,0] = "#{filename}: "
        raise
      end
    }
  end

  def LIRS.decode(f)
    lirs = LIRS.new
    f.each {|line|
      lirs << Record.decode(line) if /^#/ !~ line
    }
    lirs
  end

  def initialize
    @record = {}
  end

  def size
    @record.size
  end

  def <<(record)
    @record[record.target_url] = record
  end

  def each
    @record.each {|url, record|
      yield record
    }
  end

  def [](url)
    @record[url]
  end

  class Record
    def Record.decode(l)
      l = l.sub(/\r?\n\z/, '')
      a = []
      l.scan(/((?:[^,\\]|\\[\0-\377])*),/) {|quoted_field,|
	a.push(quoted_field.gsub(/\\([\0-\377])/) { $1 })
      }
      record_header = a.shift
      raise LIRS::Error.new("no record header") if record_header != RecordHeader
      return Record.new(*a)
    end

    def initialize(last_modified,
		   last_detected,
		   timezone,
		   content_length,
		   target_url,
		   target_title,
		   target_maintainer,
		   antenna_url,
		   *extension_fields)
      @last_modified = last_modified
      @last_detected = last_detected
      @time_zone = timezone
      @content_length = content_length
      @target_url = target_url
      @target_title = target_title
      @target_maintainer = target_maintainer
      @antenna_url = antenna_url
      @extension_fields = extension_fields
    end

    attr_reader :last_modified,
		:last_detected,
		:time_zone,
		:content_length,
		:target_url,
		:target_title,
		:target_maintainer,
		:antenna_url,
		:extension_fields

    def encode
      l = ''
      fs = [
	RecordHeader,
	@last_modified,
	@last_detected,
	@time_zone,
	@content_length,
	@target_url,
	@target_title,
	@target_maintainer,
	@antenna_url,
	*@extension_fields
      ].each {|f|
	l << f.gsub(/[,\\]/) { "\\#{$&}" } << ','
      }
      l << "\n"
      return l
    end
  end

  class Error < StandardError
  end
end
