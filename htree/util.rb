def Regexp.alt(*args)
  if args.empty?
    /(?!)/
  else
    Regexp.compile(args.map {|arg| Regexp === arg ? arg.to_s : Regexp.quote(arg) }.join('|'))
  end
end

