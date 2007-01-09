# lirs.rb - LIRS library
#
# Copyright (C) 2003,2006 Tanaka Akira  <akr@fsij.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

class LIRS
  RecordHeader = 'LIRS'

  def LIRS.load(filename)
    File.open(filename) {|f|
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
    f.each_line {|line|
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
      raise LIRS::Error.new("too few record fields") if a.length < 8
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
