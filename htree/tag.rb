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
    def extract_attrs
      return if defined? @attrs
      @attrs = []
      case @str
      when /\A#{Pat::ValidStartTag_C}\z/o, /\A#{Pat::ValidEmptyTag_C}\z/o
        tagname = $1
        $2.scan(Pat::ValidAttr_C) {
          @attrs << ($2 ? [$1.downcase, HTree.fix_character_reference($+)] : [nil, $1])
        }
      when /\A#{Pat::InvalidStartTag_C}\z/o, /\A#{Pat::InvalidEmptyTag_C}\z/o
        tagname = $1
        attrs = $2
        last_attr = $3
        attrs.scan(Pat::InvalidAttr1_C) {
          @attrs << ($2 ? [$1.downcase, HTree.fix_character_reference($+)] : [nil, $1])
        }
        if last_attr
          /#{Pat::InvalidAttr1End_C}/ =~ last_attr
          @attrs << ($2 ? [$1.downcase, HTree.fix_character_reference($+)] : [nil, $1])
        end
      else
        raise "unrecognized start tag format [bug]: #{@str.inspect}"
      end
    end

    def each_attribute_rcdata
      extract_attrs
      @attrs.each {|name, val|
        yield name, val
      }
    end

    def each_attribute_text
      each_attribute_rcdata {|name, val|
        yield name, HTree.decode_rcdata(val)
      }
    end

    def fetch_attribute_text(name, *rest)
      if 1 < rest.length
        raise ArgumentError, "wrong number of arguments(#{1 + rest.length} for 2)"
      end
      each_attribute_text {|n, v|
        return v if n == name
      }
      if block_given?
        yield
      elsif rest.length == 1
        rest[0]
      else
        raise IndexError, "attribute not found: #{name.inspect}"
      end
    end

    def inspect; "<stag: #{@str.inspect}>" end
  end

  class ETag < Tag
    def inspect; "<etag: #{@str.inspect}>" end
  end
end
