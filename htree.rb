require 'pp'

class HTree
  module Pat
    Name = %r{[A-Za-z_:][-A-Za-z0-9._:]*}
    DocType = %r{<!DOCTYPE.*?>}m
    ProcIns = %r{<\?.*?\?>}m
    StartTag = %r{<#{Name}(?:\s+#{Name}(?:=(?:'[^'>]*'|"[^">]*"|[^\s>]+))?)*\s*/?>}
    EndTag = %r{</#{Name}\s*>}
    Comment = %r{<!--.*?-->}m
  end

  class Fragment
    def initialize(str, mark)
      @str = str.dup
      @str.freeze
      @mark = mark
    end
    attr_accessor :mark

    def tagname
      Pat::Name =~ @str
      $&.downcase
    end

    def to_s
      @str
    end

    def inspect
      "<Fragment:#{@mark} #{@str.inspect}>"
    end

    def to_tree
      case @mark
      when :doctype; DocType.new(@str)
      when :procins; ProcIns.new(@str)
      when :comment; Comment.new(@str)
      when :empty; EmptyElem.new(@str)
      when :text; Text.new(@str)
      when :ignored_etag; IgnoredETag.new(@str)
      else
        raise "cannot convert to tree from fragment marked as #{@mark}"
      end
    end
  end

  class Doc
    def initialize(*elts)
      @elts = elts
    end
    def pretty_print(pp)
      pp.object_group(self) { @elts.each {|elt| pp.breakable; pp.pp elt } }
    end
    alias inspect pretty_print_inspect
  end

  class Elem
    def initialize(stag, *elts)
      @stag = stag.to_s
      @elts = elts
      @etag = nil
      @etag = elts.pop.to_s if !elts.empty? && Fragment === elts.last && elts.last.mark == :etag
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

  module Leaf
    def initialize(tag)
      @tag = tag
    end
    def inspect; "{#{self.class.name.sub(/.*::/,'').downcase} #{@tag.inspect}}" end
  end

  class DocType; include Leaf; end
  class ProcIns; include Leaf; end
  class Comment; include Leaf; end
  class EmptyElem; include Leaf; end
  class Text; include Leaf; end
  class IgnoredETag; include Leaf; end

  def HTree.scan(str)
    text = nil
    str.scan(%r{(#{Pat::DocType})|(#{Pat::ProcIns})|(#{Pat::StartTag})|(#{Pat::EndTag})|(#{Pat::Comment})|[^<>]+|[<>]}) {
      if $+
        if text
          yield Fragment.new(text, :text)
          text = nil
        end
        if $1
          yield Fragment.new($&, :doctype)
        elsif $2
          yield Fragment.new($&, :procins)
        elsif $3
          yield Fragment.new($&, :stag)
        elsif $4
          yield Fragment.new($&, :etag)
        else
          yield Fragment.new($&, :comment)
        end
      else
        text ||= ''
        text << $&
      end
    }
    yield Fragment.new(text, :text) if text
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
      if f.mark == :stag && %r{/>\z} =~ f.to_s
        f.mark = :empty
      end
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
  OmissibleTags = %w[body tbody head html]
  TagInfo.each {|tag, (children,)|
    ootags = children & OmissibleTags
    unless ootags.empty?
      ootags.each {|ootag|
        children |= TagInfo[ootag][0]
      }
    end
    TagInfo[tag][0] = children
  }

  def HTree.parse_pairs(frags)
    stack = [[TagInfo['/'].first, [], [], nil]]
    frags.each {|f|
      case f.mark
      when :empty, :stag
        parent_elts = nil
        stack.reverse_each {|elts|
          possible_tags, forbidden_tags, additional_tags = elts
          possible_tags = (possible_tags | additional_tags) - forbidden_tags
          if possible_tags.include? f.tagname
            parent_elts = elts
            break
          end
        }
        if parent_elts
          until stack.last.equal? parent_elts
            elts = stack.pop
            stack.last.push Elem.new(*elts[3..-1])
          end
        end
        if f.mark == :empty
          stack.last << f.to_tree
        else
          possible_sibling_tags, forbidden_tags, additional_tags = stack.last
          possible_tags, forbidden_tags2, additional_tags2 = TagInfo[f.tagname]
          possible_tags = possible_sibling_tags unless possible_tags
          forbidden_tags |= forbidden_tags2 if forbidden_tags2
          additional_tags |= additional_tags2 if additional_tags2
          stack << [possible_tags, forbidden_tags, additional_tags, f]
        end
      when :etag
        target_elts = nil
        stack.reverse_each {|elts|
          _, _, _, first_elt, = elts
          if Fragment === first_elt && first_elt.mark == :stag && first_elt.tagname == f.tagname
            target_elts = elts
            break
          end
        }
        if target_elts
          until stack.last.equal? target_elts
            elts = stack.pop
            stack.last.push Elem.new(*elts[3..-1])
          end
          stack.last << f
          elts = stack.pop
          stack.last.push Elem.new(*elts[3..-1])
        else
          f.mark = :ignored_etag
          stack.last << f.to_tree
        end
      else
        stack.last << f.to_tree
      end
    }
    until stack.length == 1
      elts = stack.pop
      stack.last.push Elem.new(*elts[3..-1])
    end
    Doc.new(*stack.first[4..-1])
  end

  def HTree.parse(str)
    parse_pairs(parse_empties(str))
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
  </body>
</html>
End
  else
    str = ARGF.read
  end
  #HTree.scan(str) {|s| p [s.mark, s] if /\S/ =~ s }
  pp HTree.parse(str)
end
