require 'pp'
require 'mconv'

def Regexp.alt(*args)
  if args.empty?
    /(?!)/
  else
    Regexp.compile(args.map {|arg| Regexp === arg ? arg.to_s : Regexp.quote(arg) }.join('|'))
  end
end

module HTree
  module Pat
    Name = %r{[A-Za-z_:][-A-Za-z0-9._:]*}
    DocType = %r{<!DOCTYPE.*?>}m
    ProcIns = %r{<\?.*?\?>}m
    StartTag = %r{<#{Name}(?:\s+#{Name}(?:\s*=\s*(?:'[^'>]*'|"[^">]*"|[^\s>]*))?)*\s*>}
    EndTag = %r{</#{Name}\s*>}
    EmptyTag = %r{<#{Name}(?:\s+#{Name}(?:\s*=\s*(?:'[^'>]*'|"[^">]*"|[^\s>]*))?)*\s*/>}
    Comment = %r{<!--.*?-->}m
  end

  class Tag
    def initialize(str)
      @str = str
      @prefix = []
      @suffix = []
    end
    attr_accessor :prefix, :suffix

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

  module Node
    def text
      str = self.html_text
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

    def root
      @elts.each {|e|
        return e if Elem === e
      }
      nil
    end

    def each_element(name=nil)
      @elts.each {|elt|
        elt.each_element(name) {|e|
          yield e
        }
      }
    end

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

    def html_text
      text = ''
      @elts.each {|elt| text << elt.html_text }
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

    def pretty_print(pp)
      pp.group(1, "{elem", "}") {
        pp.breakable; pp.pp @stag
        @elts.each {|elt| pp.breakable; pp.pp elt }
        pp.breakable; pp.pp @etag
      }
    end
    alias inspect pretty_print_inspect

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

    def html_text
      text = ''
      @elts.each {|elt| text << elt.html_text }
      text
    end
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
    def html_text; '' end
  end
  class ProcIns
    include Leaf
    def each_element(name=nil) end
    def html_text; '' end
  end
  class Comment
    include Leaf
    def each_element(name=nil) end
    def html_text; '' end
  end
  class EmptyElem
    include Leaf
    def extract_taginfo
      return if defined? @tagname
      if @str
        Pat::Name =~ @str
        @tagname = $&.downcase
      else
        @tagname = nil
      end
    end
    def tagname
      extract_taginfo
      @tagname
    end
    def each_element(name=nil)
      yield self if name == nil || self.tagname == name
    end
    def html_text; '' end
  end
  class BogusETag
    include Leaf
    def each_element(name=nil) end
    def html_text; '' end
  end
  class Text
    include Leaf
    def each_element(name=nil) end
    QuoteHash = { '<'=>'&lt;', '>'=> '&gt;' }
    def html_text
      return @text if defined? @text
      @text = ''
      @text = HTree.fix_character_reference(@str).gsub(/[<>]/) { QuoteHash[$&] }
      @text
    end
  end

  # HTML 4.01
  NamedCharacters = {
    "nbsp" => 160, "iexcl" => 161, "cent" => 162, "pound" => 163,
    "curren" => 164, "yen" => 165, "brvbar" => 166, "sect" => 167, "uml" => 168,
    "copy" => 169, "ordf" => 170, "laquo" => 171, "not" => 172, "shy" => 173,
    "reg" => 174, "macr" => 175, "deg" => 176, "plusmn" => 177,
    "sup2" => 178, "sup3" => 179, "acute" => 180, "micro" => 181, "para" => 182,
    "middot" => 183, "cedil" => 184, "sup1" => 185, "ordm" => 186,
    "raquo" => 187, "frac14" => 188, "frac12" => 189, "frac34" => 190,
    "iquest" => 191,
    "Agrave" => 192, "Aacute" => 193, "Acirc" => 194, "Atilde" => 195,
    "Auml" => 196, "Aring" => 197, "AElig" => 198, "Ccedil" => 199,
    "Egrave" => 200, "Eacute" => 201, "Ecirc" => 202, "Euml" => 203,
    "Igrave" => 204, "Iacute" => 205, "Icirc" => 206, "Iuml" => 207,
    "ETH" => 208, "Ntilde" => 209,
    "Ograve" => 210, "Oacute" => 211, "Ocirc" => 212, "Otilde" => 213,
    "Ouml" => 214, "times" => 215, "Oslash" => 216,
    "Ugrave" => 217, "Uacute" => 218, "Ucirc" => 219, "Uuml" => 220,
    "Yacute" => 221, "THORN" => 222,
    "szlig" => 223, "agrave" => 224, "aacute" => 225, "acirc" => 226,
    "atilde" => 227, "auml" => 228, "aring" => 229, "aelig" => 230,
    "ccedil" => 231,
    "egrave" => 232, "eacute" => 233, "ecirc" => 234, "euml" => 235,
    "igrave" => 236, "iacute" => 237, "icirc" => 238, "iuml" => 239,
    "eth" => 240, "ntilde" => 241,
    "ograve" => 242, "oacute" => 243, "ocirc" => 244, "otilde" => 245,
    "ouml" => 246, "divide" => 247, "oslash" => 248,
    "ugrave" => 249, "uacute" => 250, "ucirc" => 251, "uuml" => 252,
    "yacute" => 253, "thorn" => 254, "yuml" => 255,
    "quot" => 34, "amp" => 38, "lt" => 60, "gt" => 62,
    "OElig" => 338, "oelig" => 339,
    "Scaron" => 352, "scaron" => 353,
    "Yuml" => 376, "circ" => 710, "tilde" => 732, "ensp" => 8194,
    "emsp" => 8195, "thinsp" => 8201, "zwnj" => 8204, "zwj" => 8205,
    "lrm" => 8206, "rlm" => 8207, "ndash" => 8211, "mdash" => 8212,
    "lsquo" => 8216, "rsquo" => 8217, "sbquo" => 8218,
    "ldquo" => 8220, "rdquo" => 8221, "bdquo" => 8222,
    "dagger" => 8224, "Dagger" => 8225, "permil" => 8240,
    "lsaquo" => 8249, "rsaquo" => 8250, "euro" => 8364, "fnof" => 402,
    "Alpha" => 913, "Beta" => 914, "Gamma" => 915, "Delta" => 916,
    "Epsilon" => 917, "Zeta" => 918, "Eta" => 919, "Theta" => 920,
    "Iota" => 921, "Kappa" => 922, "Lambda" => 923, "Mu" => 924,
    "Nu" => 925, "Xi" => 926, "Omicron" => 927, "Pi" => 928, "Rho" => 929,
    "Sigma" => 931, "Tau" => 932, "Upsilon" => 933, "Phi" => 934, "Chi" => 935,
    "Psi" => 936, "Omega" => 937,
    "alpha" => 945, "beta" => 946, "gamma" => 947, "delta" => 948,
    "epsilon" => 949, "zeta" => 950, "eta" => 951, "theta" => 952,
    "iota" => 953, "kappa" => 954, "lambda" => 955, "mu" => 956, "nu" => 957,
    "xi" => 958, "omicron" => 959, "pi" => 960, "rho" => 961, "sigmaf" => 962,
    "sigma" => 963, "tau" => 964, "upsilon" => 965, "phi" => 966, "chi" => 967,
    "psi" => 968, "omega" => 969, "thetasym" => 977, "upsih" => 978,
    "piv" => 982, "bull" => 8226, "hellip" => 8230, "prime" => 8242,
    "Prime" => 8243, "oline" => 8254, "frasl" => 8260, "weierp" => 8472,
    "image" => 8465, "real" => 8476, "trade" => 8482, "alefsym" => 8501,
    "larr" => 8592, "uarr" => 8593, "rarr" => 8594, "darr" => 8595,
    "harr" => 8596, "crarr" => 8629, "lArr" => 8656, "uArr" => 8657,
    "rArr" => 8658, "dArr" => 8659, "hArr" => 8660, "forall" => 8704,
    "part" => 8706, "exist" => 8707, "empty" => 8709, "nabla" => 8711,
    "isin" => 8712, "notin" => 8713, "ni" => 8715, "prod" => 8719,
    "sum" => 8721, "minus" => 8722, "lowast" => 8727, "radic" => 8730,
    "prop" => 8733, "infin" => 8734, "ang" => 8736, "and" => 8743, "or" => 8744,
    "cap" => 8745, "cup" => 8746, "int" => 8747, "there4" => 8756,
    "sim" => 8764, "cong" => 8773, "asymp" => 8776, "ne" => 8800,
    "equiv" => 8801, "le" => 8804, "ge" => 8805, "sub" => 8834, "sup" => 8835,
    "nsub" => 8836, "sube" => 8838, "supe" => 8839, "oplus" => 8853,
    "otimes" => 8855, "perp" => 8869, "sdot" => 8901, "lceil" => 8968,
    "rceil" => 8969, "lfloor" => 8970, "rfloor" => 8971, "lang" => 9001,
    "rang" => 9002, "loz" => 9674, "spades" => 9824, "clubs" => 9827,
    "hearts" => 9829, "diams" => 9830,
  }
  Pat::NamedCharacters = /\A#{Regexp.alt *NamedCharacters.keys}\z/

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

  EmptyTags = %w[
    basefont br area link img param hr input col frame isindex base meta
  ]
  EmptyTags.concat %w[
    wbr
  ] # http://wp.netscape.com/assist/net_sites/html_extensions.html
  EmptyTagHash = {}
  EmptyTags.each {|tag| EmptyTagHash[tag] = tag }

  def HTree.parse_empties(str)
    frags = []
    HTree.scan(str) {|f|
      frags << f
    }
    last_tag = nil
    frags.reverse_each {|f|
      if f.mark == :stag && EmptyTagHash[f.tagname] &&
         !(last_tag && last_tag.mark == :etag && last_tag.tagname == f.tagname)
        f.mark = :empty
      end
      last_tag = f if f.mark == :stag || f.mark == :etag
    }
    frags
  end

  head_misc = %w[script style meta link object]
  heading = %w[h1 h2 h3 h4 h5 h6]
  list = %w[ul ol dir menu]
  preformatted = %w[pre]
  fontstyle = %w[tt i b u s strike big small]
  phrase = %w[em strong dfn code samp kbd var cite abbr acronym]
  special = %w[a img applet object font basefont br script map q sub sup span bdo iframe]
  formctrl = %w[input select textarea label button]
  inline = fontstyle + phrase + special + formctrl
  block = heading + list + preformatted +
    %w[p dl div center noscript noframes blockquote form isindex hr table fieldset address]
  flow = block + inline

  TagInfo = {
    'tt' => [inline],
    'i' => [inline],
    'b' => [inline],
    'u' => [inline],
    's' => [inline],
    'strike' => [inline],
    'big' => [inline],
    'small' => [inline],
    'em' => [inline],
    'strong' => [inline],
    'dfn' => [inline],
    'code' => [inline],
    'samp' => [inline],
    'kbd' => [inline],
    'var' => [inline],
    'cite' => [inline],
    'abbr' => [inline],
    'acronym' => [inline],
    'sub' => [inline],
    'sup' => [inline],
    'span' => [inline],
    'bdo' => [inline],
    'font' => [inline],
    'body' => [block + %w[script], nil, %w[ins del]],
    'address' => [inline + %w[p]],
    'div' => [flow],
    'center' => [flow],
    'a' => [inline, %w[a]],
    'map' => [block + %w[area]],
    'object' => [flow + %w[param]],
    'applet' => [flow + %w[param]],
    'p' => [inline],
    'h1' => [inline],
    'h2' => [inline],
    'h3' => [inline],
    'h4' => [inline],
    'h5' => [inline],
    'h6' => [inline],
    'pre' => [inline, %w[img object applet big small sub sup font basefont]],
    'q' => [inline],
    'blockquote' => [flow],
    'ins' => [flow],
    'del' => [flow],
    'dl' => [%w[dt dd]],
    'dt' => [inline],
    'dd' => [flow],
    'ol' => [%w[li]],
    'ul' => [%w[li]],
    'dir' => [%w[li], block],
    'menu' => [%w[li], block],
    'li' => [flow],
    'form' => [flow, %w[form]],
    'label' => [inline, %w[label]],
    'select' => [%w[optgroup option]],
    'optgroup' => [%w[option]],
    'option' => [%w[]],
    'textarea' => [%w[]],
    'fieldset' => [flow + %w[legend]],
    'legend' => [inline],
    'button' => [flow, formctrl + %w[a form isindex fieldset iframe]],
    'table' => [%w[caption col colgroup thead tfoot tbody]],
    'caption' => [inline],
    'thead' => [%w[tr]],
    'tfoot' => [%w[tr]],
    'tbody' => [%w[tr]],
    'colgroup' => [%w[col]],
    'tr' => [%w[th td]],
    'th' => [flow],
    'td' => [flow],
    'frameset' => [%w[frameset frame noframes]],
    'iframe' => [flow],
    'noframes' => [flow + %w[body]],
    'head' => [%w[title isindex base] + head_misc],
    'title' => [%w[]],
    'style' => [%w[]],
    'script' => [%w[]],
    'noscript' => [flow],
    'html' => [%w[head body frameset]],
    '/' => [%w[html]]
  }
  OmissibleTags = %w[tbody body head html]
  TagInfo.each {|tag, (children,)|
    ootags = children & OmissibleTags
    unless ootags.empty?
      ootags.each {|ootag|
        children |= TagInfo[ootag][0]
      }
    end
    TagInfo[tag][0] = children
  }

  def HTree.parse(str)
    elts = []
    scan(str) {|elt|
      elts << elt
    }
    elts = parse_pairs(elts)
    elts.each_with_index {|elt, i|
      if Elem === elt && !elt.etag
        elts[i] = Elem.new(elt.stag, elt.elts, true)
      end
    }
    elts = fix_elts(elts)
    elts.each_with_index {|elt, i|
      if Elem === elt && elt.etag == true
        elts[i] = Elem.new(elt.stag, elt.elts, nil)
      end
    }
    Doc.new(elts)
  end

  def HTree.scan(str)
    text = nil
    str.scan(%r{(#{Pat::DocType})|(#{Pat::ProcIns})|(#{Pat::StartTag})|(#{Pat::EndTag})|(#{Pat::EmptyTag})|(#{Pat::Comment})|[^<>]+|[<>]}o) {
      if $+
        if text
          yield Text.new(text)
          text = nil
        end
        if $1
          yield DocType.new($&)
        elsif $2
          yield ProcIns.new($&)
        elsif $3
          yield STag.new($&)
        elsif $4
          yield ETag.new($&)
        elsif $5
          yield EmptyElem.new($&)
        else
          yield Comment.new($&)
        end
      else
        text ||= ''
        text << $&
      end
    }
    yield Text.new(text) if text
  end

  def HTree.parse_pairs(elts)
    result = []
    stack = [[nil]]
    elts.each {|elt|
      case elt
      when STag
        stack << [elt]
      when ETag
        match = nil
        etagname = elt.tagname
        stack.reverse_each {|es|
          if es.first && es.first.tagname == etagname
            match = es
            break
          end
        }
        if match
          elem = nil
          until match.equal? stack.last
            stack.last << elem if elem
            es_elts = stack.pop
            es_stag = es_elts.shift
            elem = Elem.new(es_stag, es_elts)
          end
          es_elts = stack.pop
          es_stag = es_elts.shift
          es_elts << elem if elem
          stack.last << Elem.new(es_stag, es_elts, elt)
        else
          stack.last << BogusETag.new(elt.to_s)
        end
      else
        stack.last << elt
      end
    }
    elem = nil
    while stack.last.first
      es_elts = stack.pop
      es_stag = es_elts.shift
      elem = Elem.new(es_stag, es_elts)
      stack.last << elem
    end
    elts.replace stack.first[1..-1]
  end

  def HTree.fix_elts(elts)
    result = []
    rest = elts.dup
    until rest.empty?
      elt = rest.shift
      if Elem === elt
        elem, rest2 = fix_elem(elt, TagInfo['/'].first, [], [])
        result << elem
        rest = rest2 + rest
      else
        result << elt
      end
    end
    result
  end

  def HTree.fix_elem(elem, possible_sibling_tags, forbidden_tags, additional_tags)
    if elem.etag
      return Elem.new(elem.stag, fix_elts(elem.elts), elem.etag), []
    else
      tagname = elem.tagname
      if EmptyTagHash[tagname]
        return EmptyElem.new(elem.stag.to_s), elem.elts
      else
        possible_tags, forbidden_tags2, additional_tags2 = TagInfo[tagname]
        possible_tags = possible_sibling_tags unless possible_tags
        forbidden_tags |= forbidden_tags2 if forbidden_tags2
        additional_tags |= additional_tags2 if additional_tags2
        containable_tags = (possible_tags | additional_tags) - forbidden_tags
        fixed_elts = []
        rest = elem.elts.dup
        until rest.empty?
          elt = rest.shift
          if Elem === elt
            if containable_tags.include? elt.tagname
              elt, rest2 = fix_elem(elt, possible_tags, forbidden_tags, additional_tags)
              fixed_elts << elt
              rest = rest2 + rest
            else
              rest.unshift elt
              break
            end
          else
            fixed_elts << elt
          end
        end
        return Elem.new(elem.stag, fixed_elts), rest
      end
    end
  end

end

if $0 == __FILE__
  #pp HTree::TagInfo
  if ARGV.empty? && STDIN.tty?
    str = <<'End'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
  "http://www.w3.org/TR/html4/strict.dtd">
<? sss fd ?>
<html lang=ja>
  <head>
    <title>This is a title.</title>
  </head>
  <body background="white">
     simple < a >
    <p>para
    <hr>
    </z>
    <ul>
    <ins>aa</ins>
    <li
    >a<li
    ><b>b</b>
    <li><b>x<i>y</b>z</i></ul>
    <hr />
    <hr/>
    <hr> </hr>
    <hr><!-- aaa --> </hr>
    a<div>b<hr>c</div>d
    <li>
    <li>
  </body>
  <li>
  <li>
End
  else
    str = ARGF.read
  end
  #HTree.scan(str) {|s| p [s.mark, s] if /\S/ =~ s }
  pp HTree.parse(str)
end
