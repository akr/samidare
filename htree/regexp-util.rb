unless defined? Regexp.union
  def Regexp.union(*args)
    if args.empty?
      /(?!)/
    else
      Regexp.compile(args.map {|arg| Regexp === arg ? arg.to_s : Regexp.quote(arg) }.join('|'))
    end
  end
end

class Regexp
  def disable_capture
    re = ''
    self.source.scan(/\\.|[^\\\(]+|\(\?|\(/m) {|s|
      if s == '('
        re << '(?:'
      else
        re << s
      end
    }
    Regexp.new(re, self.options, self.kcode)
  end
end

