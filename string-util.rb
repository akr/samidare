require 'zlib'
require 'stringio'

class String
  def decode_gzip
    Zlib::GzipReader.new(StringIO.new(self)).read
  end
  
  def decode_deflate
    Zlib::Inflate.inflate(self)
  end
end

