require 'htree/regexp-util'

class HTree
  class DTD
    def DTD.parse(str)
      dtd = DTD.new
      dtd.parse(str)
      dtd
    end

    Name = /[A-Za-z_:][-A-Za-z0-9._:]*/
    Nmtoken = /[-A-Za-z0-9._:]+/
    Comment = /--.*?--/m
    ParaEntRef = /%(#{Name});?/
    MarkupDecl = /<!(?:#{Comment}|.)*?>/m
    MarkedSectDecl = /<!\[.*?\]\]>/m

    RE = /#{MarkedSectDecl}
         |#{MarkupDecl}
         |#{ParaEntRef.disable_capture}
         |\s+|./x

    def initialize
      @elems = {}
      @para_ents = {}
      @ents = {}
    end

    def element_names
      @elems.keys.sort
    end

    def elements
      @elems.values
    end

    def entites
      @ents
    end

    def parse(str)
      para_ents = {}
      str.scan(RE) {|s|
        next if /\A\s+\z/ =~ s
        s.gsub!(Comment, '')
        next if s == '<!>'
        s.sub!(/\s+>/, '>')
        s.gsub!(ParaEntRef) {|ent| @para_ents[$1] || $& }
        case s
        when /\A<!ENTITY\s+%\s+(#{Name})\s+"([^"]*)">\z/mo
          @para_ents[$1] = $2
        when /\A<!ENTITY\s+(#{Name})\s+CDATA\s+"([^"]*)">\z/mo
          @ents[$1] = $2
        when /\A<!ELEMENT/
          parse_element(s)
        when /\A<!ATTLIST/
          parse_attlist(s)
        when /\A<!\[ IGNORE/
          # ignore
        else
          #p s
        end
      }
    end

    def parse_element(str)
      str = str.dup
      str.sub!(/\A<!ELEMENT\s+/, '')
      case str
      when /\A(#{Name})\s+/o
        str = $'
        elts = [$1]
      when /\A\(\s*(#{Name}(?:\s*\|\s*#{Name})*)\s*\)\s+/o
        str = $'
        elts = $1.scan(Name)
      else
        raise "unexpected element name(s): #{str.inspect}"
      end

      elems = []
      elts.each {|elt|
        elt = elt.downcase
        @elems[elt] ||= Element.new(elt)
        elems << @elems[elt]
      }

      case str
      when /\AO\s+/
        elems.each {|elem| elem.omit_stag = true }
      when /\A-\s+/
        elems.each {|elem| elem.omit_stag = false }
      else
        raise "unexpected omit-stag : #{str.inspect}"
      end
      str = $'

      case str
      when /\AO\s+/
        elems.each {|elem| elem.omit_etag = true }
      when /\A-\s+/
        elems.each {|elem| elem.omit_etag = false }
      else
        raise "unexpected omit-stag : #{str.inspect}"
      end
      str = $'

      case str
      when /\A(CDATA|RCDATA|EMPTY)\b\s*/
        elems.each {|elem| elem.content = $1.intern }
      else
        str.sub!(/\s*>\z/, '')
        if /\s*\+\(\s*(#{Name}(?:\s*\|\s*#{Name})*)\s*\)\z/o =~ str
          str = $`
          inclusions = $1.scan(Name).map {|name| name.downcase }
          elems.each {|elem| elem.inclusions = inclusions }
        end
        if /\s*-\(\s*(#{Name}(?:\s*\|\s*#{Name})*)\s*\)\z/o =~ str
          str = $`
          exclusions = $1.scan(Name).map {|name| name.downcase }
          elems.each {|elem| elem.exclusions = exclusions }
        end
        str.gsub!(/\s+/, ' ')
        content, rest = parse_and(str)
        if /\S/ =~ rest
          raise "unexpected content : #{rest.inspect}"
        end
        elems.each {|elem| elem.content = content }
      end
    end

    def parse_model_group(str)
      raise "open-paren expected : #{str.inspect}" unless /\A\(\s*/ =~ str
      content, str = parse_and($')
      raise "close-paren expected : #{str.inspect}" unless /\A\)\s*/ =~ str
      return content, $'
    end

    def parse_content_token(str)
      case str
      when /\A\(/
        parse_model_group(str)
      when /\A(#PCDATA)\b\s*/
        return $1, $'
      when /\A(#{Name})\b\s*/
        return $1.downcase, $'
      else
        raise "content-token expected : #{str.inspect}"
      end
    end

    OccurenceMark = {
      "?" => :opt,
      "+" => :plus,
      "*" => :rep,
    }
    def parse_occurence_mark(str)
      content, str = parse_content_token(str)
      if /\A([?+*])\s*/ =~ str
        return [OccurenceMark[$1], content], $'
      else
        return content, str
      end
    end

    def parse_seq(str)
      cs = [:seq]
      begin
        str = $' if $~
        content, str = parse_occurence_mark(str)
        if Array === content && content.first == cs.first
          cs.concat content[1..-1]
        else
          cs << content
        end
      end while /\A,\s*/ =~ str
      if cs.length == 2
        return cs.last, str
      else
        return cs, str
      end
    end

    def parse_or(str)
      cs = [:or]
      begin
        str = $' if $~
        content, str = parse_seq(str)
        if Array === content && content.first == cs.first
          cs.concat content[1..-1]
        else
          cs << content
        end
      end while /\A\|\s*/ =~ str
      if cs.length == 2
        return cs.last, str
      else
        return cs, str
      end
    end

    def parse_and(str)
      cs = [:and]
      begin
        str = $' if $~
        content, str = parse_or(str)
        if Array === content && content.first == cs.first
          cs.concat content[1..-1]
        else
          cs << content
        end
      end while /\A&\s*/ =~ str
      if cs.length == 2
        return cs.last, str
      else
        return cs, str
      end
    end

    def parse_attlist(str)
      str = str.dup
      str.sub!(/\A<!ATTLIST\s+/, '')
      case str
      when /\A(#{Name})\s+/o
        str = $'
        elts = [$1]
      when /\A\(\s*(#{Name}(?:\s*\|\s*#{Name})*)\s*\)\s+/o
        str = $'
        elts = $1.scan(Name)
      else
        raise "unexpected element name(s): #{str.inspect}"
      end

      attrs = []
      until str.empty?
        case str
        when /\A(#{Name})\s+/o
          str = $'
          name = $1
        when /\A>/
          break
        else
          raise "unexpected attribute name: #{str.inspect}"
        end

        case str
        when /\A(#{Nmtoken})\s+/o
          str = $'
          val = $1
        when /\A\(\s*(#{Nmtoken}(?:\s*\|\s*#{Nmtoken})*)\s*\)\s+/o
          str = $'
          val = $1.scan(Nmtoken)
        else
          raise "unexpected attribute definition: #{str.inspect}"
        end

        case str
        when /\A(#{Nmtoken})\b\s*/o
          str = $'
          default = $1
        when /\A("[^"]*")\s*/
          str = $'
          default = $1
        when /\A(#(?:IMPLIED|REQUIRED|CURRENT|CONREF))\b\s*/
          str = $'
          default = $1
        when /\A(#FIXED\s+(?:"[^"]*"|'[^']*'))\s*/
          str = $'
          default = $1
        when /\A(#FIXED\s+#{Nmtoken})\b\s*/o
          str = $'
          default = $1
        else
          raise "unexpected attribute default: #{str.inspect}"
        end

        attrs << [name, val, default]
      end

      elts.each {|elt|
        elt = elt.downcase
        @elems[elt] ||= Element.new(elt)
        elem = @elems[elt]
        attrs.each {|attr|
          name, val, default = attr
          elem.define_attr(name, val, default)
        }
      }
    end

    def containable_elements(name)
      q = [name]
      result = {}
      until q.empty?
        elem = @elems[q.shift]
        elem.containable_elements.each {|e|
          unless result[e]
            result[e] = true
            q << e if @elems[e].omit_stag && @elems[e].omit_etag
          end
        }
      end
      result.keys.sort
    end

    class Element
      def initialize(name)
        @name = name
        @attrs = {}
        @omit_stag = nil
        @omit_etag = nil
        @content = nil
        @inclusions = nil
        @exclusions = nil
      end
      attr_reader :name, :attrs
      attr_accessor :omit_stag, :omit_etag, :content, :inclusions, :exclusions

      def define_attr(name, val, default)
        @attrs[name] = [val, default]
      end

      def empty_element?
        @content == :EMPTY
      end

      def cdata_element?
        @content == :CDATA
      end

      def containable_elements
        [@content].flatten.grep(String).find_all {|s| /\A#/ !~ s }
      end
    end
  end
end

if $0 == __FILE__
  require 'pp'
  arg = ARGV.first || '.'
  dtd = HTree::DTD.new
  if FileTest.directory? arg
    dtd.parse(File.read("#{arg}/HTMLlat1.ent"))
    dtd.parse(File.read("#{arg}/HTMLspecial.ent"))
    dtd.parse(File.read("#{arg}/HTMLsymbol.ent"))
    dtd.parse(File.read("#{arg}/loose.dtd"))
  else
    dtd.parse(File.read(arg))
  end

  ents = dtd.entites
  named_characters = {}
  ents.keys.sort_by {|name|
    ents[name] }.map {|name|
    /\d+/ =~ ents[name]
    named_characters[name] = $&.to_i
  }
  named_characters['apos'] = 39 # XML 1.0
  named_characters.instance_variable_set(:@mypp, true)
  pat_named_characters = /\A#{Regexp.alt(*named_characters.keys.sort)}\z/

  element_content = {}
  dtd.elements.each {|elem|
    if Symbol === elem.content
      element_content[elem.name] = elem.content
    else
      element_content[elem.name] = dtd.containable_elements(elem.name)
      element_content[elem.name].instance_variable_set(:@mypp, true)
    end
  }

  element_exclusions = {}
  element_inclusions = {}
  dtd.elements.each {|elem|
    element_exclusions[elem.name] = elem.exclusions.sort if elem.exclusions
    element_inclusions[elem.name] = elem.inclusions.sort if elem.inclusions
  }
  element_exclusions.each {|k, v| v.instance_variable_set(:@mypp, true) }
  element_inclusions.each {|k, v| v.instance_variable_set(:@mypp, true) }

  omitted_attr_name = {}
  dtd.elements.each {|elem|
    elem_name = elem.name
    val2name = {}
    elem.attrs.each {|attr_name, (val, default)|
      next unless Array === val
      val.each {|v|
        val2name[v.downcase] = attr_name
      }
    }
    omitted_attr_name[elem_name] = val2name unless val2name.empty?
  }
  omitted_attr_name.each {|k, v| v.instance_variable_set(:@mypp, true) }

  class Array
    alias pretty_print1 pretty_print
    def pretty_print2(pp)
      pp.group(1, '[', ']') {
        self.each {|v|
          pp.group { pp.comma_breakable } unless pp.first?
          pp.pp v
        }
      }
    end

    def pretty_print(pp)
      if defined? @mypp
        pretty_print2(pp)
      else
        pretty_print1(pp)
      end
    end
  end

  class Hash
    alias pretty_print1 pretty_print
    def pretty_print2(pp)
      pp.group(1, '{', '}') {
        self.keys.sort.each {|k|
          v = self[k]
          pp.group { pp.comma_breakable } unless pp.first?
          pp.group {
            pp.pp k
            pp.text '=>'
            pp.group(1) {
              pp.breakable ''
              pp.pp v
            }
          }
        }
      }
    end

    def pretty_print(pp)
      if defined? @mypp
        pretty_print2(pp)
      else
        pretty_print1(pp)
      end
    end
  end

  puts <<"End"
# The code below is auto-generated.  Don't edit manually.
module HTree
  NamedCharacters =
#{PP.pp(named_characters, '')}

  module Pat
    NamedCharacters = #{pat_named_characters.inspect}
  end

  ElementContent =
#{PP.pp(element_content, '')}
  ElementInclusions =
#{PP.pp(element_inclusions, '')}
  ElementExclusions =
#{PP.pp(element_exclusions, '')}
  OmittedAttrName =
#{PP.pp(omitted_attr_name, '')}
end
# The code above is auto-generated.  Don't edit manually.
End

end
