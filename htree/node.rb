require 'mconv'
require 'pp'
require 'htree/html'

module HTree
  def HTree.decode_rcdata(str)
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

  module Node
    def text 
      HTree.decode_rcdata(self.rcdata)
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

    def each
      @elts.each {|e| yield e }
    end

    def each_with_path
      count = {}
      @elts.each {|elt|
        node_test = elt.node_test
        count[node_test] ||= 0
        count[node_test] += 1
      }
      pos = {}
      @elts.each {|elt|
        node_test = elt.node_test
        pos[node_test] ||= 0
        n = pos[node_test] += 1
        child_path = node_test
        child_path += "[#{n}]" unless n == 1 && count[node_test] == 1
        yield elt, child_path
      }
    end

    def traverse
      yield self
      @elts.each {|elt|
        elt.traverse {|e| yield e }
      }
    end

    def traverse_with_path
      path = '/'
      yield self, path
      self.each_with_path {|elt, relpath|
        elt.traverse_with_path(path + relpath) {|e, p|
          yield e, p
        }
      }
    end

    def fold_element
      elts = []
      @elts.each {|elt|
        elts << elt.fold_element {|e, es| yield e, es }
      }
      Doc.new(elts)
    end

    # second argument for not-found?
    def first_element(name)
      self.traverse {|e|
        next unless Elem === e
        next unless e.tagname == name
        return e
      }
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

    def initialize(stag, elts=nil, etag=nil)
      @stag = stag
      @elts = elts
      @etag = etag
    end
    attr_reader :stag, :elts, :etag

    def empty_element?
      @elts == nil
    end

    def tag
      @stag
    end

    def tagname
      @stag.tagname
    end
    alias node_test tagname

    def each
      return unless @elts
      @elts.each {|e| yield e }
    end

    def each_with_path
      return unless @elts
      count = {}
      @elts.each {|elt|
        node_test = elt.node_test
        count[node_test] ||= 0
        count[node_test] += 1
      }
      pos = {}
      @elts.each {|elt|
        node_test = elt.node_test
        pos[node_test] ||= 0
        n = pos[node_test] += 1
        child_path = node_test
        child_path += "[#{n}]" unless n == 1 && count[node_test] == 1
        yield elt, child_path
      }
    end

    def traverse
      yield self
      return unless @elts
      @elts.each {|elt|
        elt.traverse {|e| yield e }
      }
    end

    def traverse_with_path(path)
      yield self, path
      return unless @elts
      each_with_path {|elt, relpath|
        elt.traverse_with_path("#{path}/#{relpath}") {|e, p|
          yield e, p
        }
      }
    end

    def fold_element
      if @elts
        elts = []
        @elts.each {|elt|
          elts << elt.fold_element {|e, es| yield e, es }
        }
        yield self, elts
      else
        yield self, nil
      end
    end

    def raw_string
      str = ''
      str << @stag.to_s if @stag
      if @elts
        @elts.each {|elt| str << elt.raw_string }
        str << @etag.to_s if @etag
      end
      str
    end

    def rcdata
      text = ''
      if @elts
        @elts.each {|elt| text << elt.rcdata }
      end
      text
    end

    def pretty_print(pp)
      if @elts
        pp.group(1, "{elem", "}") {
          pp.breakable; pp.pp @stag
          @elts.each {|elt| pp.breakable; pp.pp elt }
          pp.breakable; pp.pp @etag
        }
      else
        pp.group(1, '{emptyelem', '}') {
          pp.breakable; pp.pp @stag
        }
      end
    end
    alias inspect pretty_print_inspect
  end

  module Leaf
    include Node

    def initialize(str)
      @str = str
    end

    def raw_string; @str; end

    def traverse
      yield self
    end

    def traverse_with_path(path)
      yield self, path
    end

    def fold_element
      self
    end

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
    def rcdata; '' end
    def node_test; 'doctype()' end
  end

  class ProcIns
    include Leaf
    def rcdata; '' end
    def node_test; 'processing-instruction()' end
  end

  class Comment
    include Leaf
    def rcdata; '' end
    def node_test; 'comment()' end
  end

  class BogusETag
    include Leaf
    def rcdata; '' end
    def node_test; 'bogus-etag()' end
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

    def node_test; 'text()' end
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
