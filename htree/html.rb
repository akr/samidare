require 'htree/util'

module HTree
  module Pat
    Name = /[A-Za-z_:][-A-Za-z0-9._:]*/

    DocType = /<!DOCTYPE.*?>/m
    ProcIns = /<\?.*?>/m
    Comment = /<!--.*?-->/m
    CDATA = /<!\[CDATA\[.*?\]\]>/m

    ValidAttr = /#{Name}(?:\s*=\s*(?:"[^"]*"|'[^']*'|[-A-Za-z._:]*))?/
    InvalidAttr = /#{Name}(?:\s*=\s*(?:'[^'<>]*'|"[^"<>]*"|[^\s<>]*))?/

    ValidStartTag = /<#{Name}(?:\s+#{ValidAttr})*\s*>/
    InvalidStartTag = /<#{Name}(?:\s+#{InvalidAttr})*\s*>/
    StartTag = /#{ValidStartTag}|#{InvalidStartTag}/

    ValidEmptyTag = %r{<#{Name}(?:\s+#{ValidAttr})*\s*/>}
    InvalidEmptyTag = %r{<#{Name}(?:\s+#{InvalidAttr})*\s*/>}
    EmptyTag = /#{ValidEmptyTag}|#{InvalidEmptyTag}/

    EndTag = %r{</#{Name}\s*>}

    XmlVersionNum = /[a-zA-Z0-9_.:-]+/
    XmlVersionInfo = /\s+version\s*=\s*(?:'#{XmlVersionNum}'|"#{XmlVersionNum}")/
    XmlEncName = /[A-Za-z][A-Za-z0-9._-]*/
    XmlEncodingDecl = /\s+encoding\s*=\s*(?:"#{XmlEncName}"|'#{XmlEncName}')/
    XmlSDDecl = /\s+standalone\s*=\s*(?:'(?:yes|no)'|"(?:yes|no)")/
    XmlDecl = /<\?xml#{XmlVersionInfo}#{XmlEncodingDecl}?#{XmlSDDecl}?\s*\?>/
  end

  NamedCharacters = {
    # HTML 4.01
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
    # XML 1.0
    "apos" => 39,
  }
  Pat::NamedCharacters = /\A#{Regexp.alt *NamedCharacters.keys}\z/

  empty_tags = %w[
    basefont br area link img param hr input col frame isindex base meta
  ]
  empty_tags.concat %w[
    wbr
  ] # http://wp.netscape.com/assist/net_sites/html_extensions.html
  EmptyTagHash = {}
  empty_tags.each {|tag| EmptyTagHash[tag] = tag }

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
  omissible_tags = %w[tbody body head html]
  TagInfo.each {|tag, (children,)|
    ootags = children & omissible_tags
    unless ootags.empty?
      ootags.each {|ootag|
        children |= TagInfo[ootag][0]
      }
    end
    TagInfo[tag][0] = children
  }

  ElementContent = {
    'style' => :cdata,
    'script' => :cdata,
  }
end
