require 'mconv'
require 'pp'
require 'htree/html'

module HTree
  module Node
    def text 
      str = self.rcdata
      str.gsub(/&(?:#([0-9]+)|#x([0-9a-fA-F]+)|([A-Za-z][A-Za-z0-9]*));/o) {|s|
        u = nil
        if $1
          u = $1.to_i
        elsif $2
          u = $2.hex
        elsif $3
          u = NamedCharacters[$3]
        end
        u && 0 <= u && u <= 0x7fffffff ? [u].pack("U").decode_charset('UTF-8') : '?'
      }
    end

    QuoteHash = { '<'=>'&lt;', '>'=> '&gt;' }
    def html_text
      self.rcdata.gsub(/[<>]/) { QuoteHash[$&] }
    end
  end

  class Doc
    include Node 

    def initialize(elts)
      @elts = elts
    end

    def pretty_print(pp)
      pp.object_group(self) { @elts.each {|elt| pp.breakable; pp.pp elt } }
    end
    alias inspect pretty_print_inspect

=begin
    def root
      @elts.each {|e|
        return e if Elem === e
      }
      nil
    end
=end

    def each_element(name=nil)
      @elts.each {|elt|
        elt.each_element(name) {|e|
          yield e
        }
      }
    end

    # second argument for not-found?
    def first_element(name)
      self.each_element(name) {|e| return e }
      nil
    end

    def title
      e = first_element('title')
      e && e.text
    end

    def raw_string
      str = ''
      @elts.each {|elt| str << elt.raw_string }
      str
    end

    def rcdata
      text = ''
      @elts.each {|elt| text << elt.rcdata }
      text
    end
  end

  class Elem
    include Node

    def initialize(stag, elts=[], etag=nil)
      @stag = stag
      @elts = elts
      @etag = etag
    end
    attr_reader :stag, :elts, :etag

    def tagname
      @stag.tagname
    end

    def each_element(name=nil)
      yield self if name == nil || self.tagname == name
      @elts.each {|elt|
        elt.each_element(name) {|e| yield e }
      }
    end

    def raw_string
      str = ''
      str << @stag.to_s if @stag
      @elts.each {|elt| str << elt.raw_string }
      str << @etag.to_s if @etag
      str
    end

    def rcdata
      text = ''
      @elts.each {|elt| text << elt.rcdata }
      text
    end

    def pretty_print(pp)
      pp.group(1, "{elem", "}") {
        pp.breakable; pp.pp @stag
        @elts.each {|elt| pp.breakable; pp.pp elt }
        pp.breakable; pp.pp @etag
      }
    end
    alias inspect pretty_print_inspect
  end

  class EmptyElem
    include Node

    def initialize(tag)
      @tag = tag
    end

    def tagname
      @tag.tagname
    end

    def each_element(name=nil)
      yield self if name == nil || self.tagname == name
    end

    def raw_string; @tag.to_s; end

    def rcdata; '' end

    def pretty_print(pp)
      pp.group(1, '{', '}') {
        pp.text self.class.name.sub(/.*::/,'').downcase
        pp.breakable; pp.pp @tag.to_s
      }
    end
    alias inspect pretty_print_inspect
  end

  module Leaf
    include Node

    def initialize(str)
      @str = str
    end

    def raw_string; @str; end

    def pretty_print(pp)
      pp.group(1, '{', '}') {
        pp.text self.class.name.sub(/.*::/,'').downcase
        @str.each_line {|line|
          pp.breakable
          pp.pp line
        }
      }
    end
    alias inspect pretty_print_inspect
  end

  class DocType
    include Leaf
    def each_element(name=nil) end
    def rcdata; '' end
  end

  class ProcIns
    include Leaf
    def each_element(name=nil) end
    def rcdata; '' end
  end

  class Comment
    include Leaf
    def each_element(name=nil) end
    def rcdata; '' end
  end

  class BogusETag
    include Leaf
    def each_element(name=nil) end
    def rcdata; '' end
  end

  class Text
    include Leaf

    def Text.create_pcdata(raw_string)
      Text.new(raw_string, HTree.fix_character_reference(raw_string))
    end

    def Text.create_cdata_content(raw_string)
      rcdata = raw_string.gsub(/&/, '&amp;')
      Text.new(raw_string, rcdata)
    end

    def Text.create_cdata_section(raw_string)
      rcdata = raw_string.sub(/\A<!\[CDATA\[/, '')
      rcdata.sub!(/\]\]>\z/, '')
      rcdata.gsub!(/&/, '&amp;')
      Text.new(raw_string, rcdata)
    end

    def initialize(raw_string, rcdata)
      @str = raw_string
      @rcdata = rcdata
    end
    attr_reader :rcdata

    def each_element(name=nil) end
  end

  # xxx: これは属性でも使うので、tag 行き?
  # Pat::NamedCharacters に依存してるから tag は html に依存?
  def HTree.fix_character_reference(str)
    str.gsub(/&(?:(?:#[0-9]+|#x[0-9a-fA-F]+|([A-Za-z][A-Za-z0-9]*));?)?/o) {|s|
      name = $1
      case s
      when /;\z/
        s
      when /\A&#/
        "#{s};"
      when '&'
        '&amp;'
      else
        if Pat::NamedCharacters =~ name
          "&#{name};"
        else
          "&amp;#{name}"
        end
      end
    }
  end

end
