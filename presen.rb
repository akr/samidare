class Presen
  def initialize(data)
    @data = data
  end
  attr_reader :data

  def current_cache(entry)
    entry['_log'].compact.reverse.inject(nil) {|h0, h1|
      if !h1['content'] || !h1['content'].exist?
        h0
      elsif !h0
        h1
      elsif (h0['checksum'] &&
             h1['checksum'] &&
             h0['checksum'] == h1['checksum']) ||
            (h0['checksum_filtered'] &&
             h1['checksum_filtered'] &&
             h0['checksum_filtered'] == h1['checksum_filtered'])
        h1
      else
        break h0
      end
    }
  end
end
