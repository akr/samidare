require 'htree/parser'

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
    <![CDATA[xxx]]>
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
    #HTree.scan(str) {|s| p [s.mark, s] if /\S/ =~ s }
    pp HTree.parse(str)
  else
    if ARGV.empty?
      str = STDIN.read
      str = str.decode_charset(str.guess_charset)
      pp HTree.parse(str)
    else
      ARGV.each {|filename|
        p filename
        str = File.read(filename)
        str = str.decode_charset(str.guess_charset)
        pp HTree.parse(str)
      }
    end
  end
end
