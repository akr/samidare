require 'htree/html'
require 'htree/tag'
require 'htree/node'

module HTree
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
    xml = false
    cdata_content = false
    text = nil
    str.scan(/(#{Pat::DocType})
             |(#{Pat::ProcIns})
             |(#{Pat::StartTag})
             |(#{Pat::EndTag})
             |(#{Pat::EmptyTag})
             |(#{Pat::Comment})
             |(#{Pat::CDATA})
             |[^<>]+|[<>]/ox) {
      if cdata_content
        if $4 && (etag = ETag.new($&)).tagname == cdata_content
          yield Text.create_cdata_content(text) if text
          text = nil
          yield etag
          cdata_content = nil
        else
          text ||= ''
          text << $&
        end
      elsif $+
        if text
          yield Text.create_pcdata(text)
          text = nil
        end
        if $1
          yield DocType.new($&)
        elsif $2
          yield ProcIns.new($&)
          xml = true if !xml && /\A#{Pat::XmlDecl}\z/o =~ $&
        elsif $3
          yield stag = STag.new($&)
          if !xml && ElementContent[stag.tagname] == :cdata
            cdata_content = stag.tagname
          end
        elsif $4
          yield ETag.new($&)
        elsif $5
          yield EmptyElem.new(STag.new($&))
        elsif $6
          yield Comment.new($&)
        elsif $7
          yield Text.create_cdata_section($&)
        else
          raise "unknown match [bug]"
        end
      else
        text ||= ''
        text << $&
      end
    }
    yield Text.create_pcdata(text) if text
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
        return EmptyElem.new(elem.stag), elem.elts
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
