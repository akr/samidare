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
          name = $1.downcase
          @attrs << ($2 ? [name, HTree.fix_character_reference($+)] : [nil, name])
        }
      when /\A#{Pat::InvalidStartTag_C}\z/o, /\A#{Pat::InvalidEmptyTag_C}\z/o
        tagname = $1
        attrs = $2
        last_attr = $3
        attrs.scan(Pat::InvalidAttr1_C) {
          name = $1.downcase
          @attrs << ($2 ? [name, HTree.fix_character_reference($+)] : [nil, name])
        }
        if last_attr
          /#{Pat::InvalidAttr1End_C}/ =~ last_attr
          name = $1.downcase
          @attrs << ($2 ? [name, HTree.fix_character_reference($+)] : [nil, name])
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

    def inspect; "<stag: #{@str.inspect}>" end
  end

  class ETag < Tag
    def inspect; "<etag: #{@str.inspect}>" end
  end
end
