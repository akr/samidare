module HTree
  class Tag
    def initialize(str)
      @str = str
    end

    def tagname
      return @tagname if defined? @tagname
      Pat::Name =~ @str
      @tagname = $&.downcase
    end

    def to_s
      @str
    end
  end

  class STag < Tag
    def inspect; "<stag: #{@str.inspect}>" end
  end

  class ETag < Tag
    def inspect; "<etag: #{@str.inspect}>" end
  end
end
