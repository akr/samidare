require 'iconv'

module Mconv
  def Mconv.internal_mime_charset
    case $KCODE
    when /\Ae/i; 'euc-jp'
    when /\As/i; 'shift_jis'
    when /\Au/i; 'utf-8'
    when /\An/i; 'iso-8859-1'
    else
      raise "unknown $KCODE: #{$KCODE.inspect}"
    end
  end

  def Mconv.valid_charset?(str)
    /\A(us-ascii|iso-2022-jp|euc-jp|shift_jis|utf-8|iso-8859-1)\z/i =~ str
  end

  def Mconv.conv(str, to, from)
    ic = Iconv.new(to, from)

    result = ''
    rest = str

    begin
      result << ic.iconv(rest)
    rescue Iconv::Failure
      result << $!.success

      rest = $!.failed

      # following processing should be customizable by block?
      result << '?'
      rest = rest[1..-1]

      retry
    end

    result << ic.close

    result
  end

  CharsetTable = {
    'us-ascii' => /\A[\s\x21-\x7e]*\z/,
    'euc-jp' =>
      /\A(?:\s                               (?# white space character)
         | [\x21-\x7e]                       (?# ASCII)
         | [\xa1-\xfe][\xa1-\xfe]            (?# JIS X 0208)
         | \x8e(?:([\xa1-\xdf])              (?# JIS X 0201 Katakana)
                 |([\xe0-\xfe]))             (?# There is no character in E0 to FE)
         | \x8f[\xa1-\xfe][\xa1-\xfe]        (?# JIS X 0212)
         )*\z/nx,
    "iso-2022-jp" => # with katakana
      /\A[\s\x21-\x7e]*                      (?# initial ascii )
         (\e\(B[\s\x21-\x7e]*                (?# ascii )
         |\e\(J[\s\x21-\x7e]*                (?# JIS X 0201 latin )
         |\e\(I[\s\x21-\x7e]*                (?# JIS X 0201 katakana )
         |\e\$@(?:[\x21-\x7e][\x21-\x7e])*   (?# JIS X 0201 )
         |\e\$B(?:[\x21-\x7e][\x21-\x7e])*   (?# JIS X 0201 )
         )*\z/nx,
    'shift_jis' =>
      /\A(?:\s                               (?# white space character)
         | [\x21-\x7e]                       (?# JIS X 0201 Latin)
         | ([\xa1-\xdf])                     (?# JIS X 0201 Katakana)
         | [\x81-\x9f\xe0-\xef][\x40-\x7e\x80-\xfc]      (?# JIS X 0208)
         | ([\xf0-\xfc][\x40-\x7e\x80-\xfc]) (?# extended area)
         )*\z/nx,
    'utf-8' =>
      /\A(?:\s
         | [\x21-\x7e]
         | [\xc0-\xdf][\x80-\xbf]
         | [\xe0-\xef][\x80-\xbf][\x80-\xbf]
         | [\xf0-\xf7][\x80-\xbf][\x80-\xbf][\x80-\xbf]
         | [\xf8-\xfb][\x80-\xbf][\x80-\xbf][\x80-\xbf][\x80-\xbf]
         | [\xfc-\xfd][\x80-\xbf][\x80-\xbf][\x80-\xbf][\x80-\xbf][\x80-\xbf]
         )*\z/nx
  }
  Preference = ['us-ascii', "iso-2022-jp", 'euc-jp', 'utf-8', 'shift_jis']

  def Mconv.guess_charset(str)
    guess_charset_list(str).first
  end

  def Mconv.guess_charset_list(str)
    case str
    when /\A\xff\xfe/; return ['utf-16le']
    when /\A\xfe\xff/; return ['utf-16be']
    end
    count = {}
    CharsetTable.each {|name, regexp|
      count[name] = 0
    }
    str.scan(/\S+/n) {|fragment|
      CharsetTable.each {|name, regexp|
        count[name] += 1 if regexp =~ fragment
      }
    }
    max = count.values.max
    count.reject! {|k, v| v != max }
    return count.keys if count.size == 1
    return ['us-ascii'] if count['us-ascii']
    
    # xxx: needs more accurate guess
    Preference.reject {|name| !count[name] }
  end

  def Mconv.minimize_charset(charset, string)
    # shortcut
    if /\A(?:euc-jp|utf-8|iso-8859-1)\z/i =~ charset
      if /\A[\x00-\x7f]*\z/ =~ string
        return 'us-ascii'
      else
        return charset
      end
    end

    charset2 = 'us-ascii'
    begin
      # round trip?
      s2 = Iconv.conv(charset, charset2, Iconv.conv(charset2, charset, string))
      return charset2 if string == s2
    rescue Iconv::Failure
    end
    charset
  end
end

class String
  def decode_charset(charset)
    Mconv.conv(self, Mconv.internal_mime_charset, charset)
  end

  def encode_charset(charset)
    Mconv.conv(self, charset, Mconv.internal_mime_charset)
  end

  def guess_charset
    Mconv.guess_charset(self)
  end

  def guess_charset_list
    Mconv.guess_charset_list(self)
  end

  def decode_charset_guess
    decode_charset(guess_charset)
  end
end

