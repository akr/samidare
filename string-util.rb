require 'zlib'
require 'stringio'

class String
  def decode_gzip
    Zlib::GzipReader.new(StringIO.new(self)).read || ""
  end

  def encode_gzip
    out = ""
    Zlib::GzipWriter.wrap(StringIO.new(out)) {|gz|
      gz << self
    }
    out
  end

  def decode_deflate
    Zlib::Inflate.inflate(self)
  end
end

