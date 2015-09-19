#!/usr/bin/env ruby

require 'fileutils'
require 'redcarpet'
require 'rss'
require 'coderay'
require 'cgi'

md = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(:with_toc_data => true), :tables => true)
md_toc = Redcarpet::Markdown.new(Redcarpet::Render::HTML_TOC, :tables => true)

prefix = '..'

url_prefix = 'http://bitcoin.peryaudo.org/'

pages = [
  ['index', 'トップ', '仮想通貨ビットコインの仕組みについて技術的に解説したサイト。'],
  ['design', 'Bitcoinの仕組み', 'だれにでも分かるように、ビットコインの仕組みの基本を解説。'],
  ['comparison', 'Bitcoinウォレットの比較', '違いの分かりづらい、Bitcoinウォレットごとの差異を仕組みの面から解説。'],
  ['detail', 'Bitcoinの細部', 'なかなか書かれることのない、Bitcoinを支える概念について解説。'],
  ['implement', 'Bitcoinウォレットを実装する', 'Rubyを使って、Bitcoinウォレットを自分の手で実装。'],
  ['malleability', 'トランザクション展性とは', 'Mt.Gox破綻の原因となったBitcoinのバグについて解説。'],
  ['derivatives', 'Bitcoinの派生通貨', 'Peercoin, Litecoinと、それを支えるProof-of-Stakeモデルについて解説。'],
  ['history', 'Bitcoinの歴史', 'Bitcoinの歴史について、その背景から解説。'],
  ['links', 'リンク集', 'Bitcoinに関係する資料などの掲載されているサイトの一覧。'],
  nil,
  ['intro', 'はじめに', '「ビットコインの仕組み」を読むべき理由について。'],
  ['sitemap', 'サイトの構成', '「ビットコインの仕組み」のサイト構成。'],
  ['background', '必要な予備知識', '「ビットコインの仕組み」を読むにあたって必要となる予備知識。']
]

orphans = []

updates = [
  ['index', '2015/9/19 17:00', 'ライセンスをCC-BY-SA-4.0に変更'],
  ['malleability', '2014/3/30 17:00', '「トランザクション展性とは」の章を追加'],
  ['implement', '2014/3/17 22:00', '「Bitcoinウォレットを実装する」の章が概ね完成'],
  ['index', '2014/3/9', '構成を改善'],
  ['index', '2014/3/5', 'このサイトを公開']
]

# generate sitemap
open("#{prefix}/sitemap.xml", 'w').write(
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
  "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" + 
  (pages + orphans).collect { |page| if page then "<url><loc>#{url_prefix}#{page[0]}.html</loc></url>" else "" end }.join("\n") +
  "\n</urlset>")

# generate pages
templ = open('template.html').read

menu = pages.collect { |page| if page then "<li><a href=\"#{page[0]}.html\">#{page[1]}</a></li>" else "</ul><ul>" end }.join("\n")

update_str = "<ul>" + updates.collect do |update|
  if update[0] == 'index' then
    "<li>#{update[1]} #{update[2]}</li>"
  else
    "<li>#{Time.parse(update[1]).strftime('%Y/%-m/%d')} <a href=\"#{update[0]}.html\">#{update[2]}</a></li>"
  end
end.join("\n") + "</ul>"

(pages + orphans).each do |page|
  unless page then
    next
  end

  result = templ

  result = result.gsub('<!--TITLE-->', page[1])

  result = result.gsub('<!--DESCRIPTION-->', page[2])

  result = result.gsub('<!--MENU-->', menu)

  md_text = open("#{page[0]}.md").read
  result = result.gsub('<!--TEXT-->', md.render(md_text))

  result = result.gsub('<!--TOC-->', "<div class=\"toc\">#{md_toc.render(md_text)}</div>") # FIXME

  result = result.gsub('<!--UPDATES-->', update_str)

  result = result.gsub(/<pre><code>(.+?)<\/code><\/pre>/m) do
    converted = CGI.unescapeHTML($1)
    CodeRay.scan(converted, :ruby).div
  end

  open("#{prefix}/#{page[0]}.html", 'w').write result
end

# generate rss
open("#{prefix}/index.rdf", 'w') do |file|
  file.write <<RSS
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
  xmlns:admin="http://webns.net/mvcb/"
  xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">

  <channel>
    <title>ビットコインの仕組み</title>
    <link>#{url_prefix}index.rdf</link>
    <description>仮想通貨ビットコインの仕組みについて技術的に徹底解説。</description>
    <language>ja</language>
RSS
  updates.each do |update|
    title = nil
    (pages + orphans).each do |page|
      next unless page
      if update[0] == page[0] then
        title = page[1]
        break
      end
    end
    file.write <<RSS
    <item>
    <title>#{title}</title>
    <link>#{url_prefix}#{update[0]}.html?#{Time.parse(update[1]).strftime("%Y%m%d")}</link>
    <description>#{update[2]}</description>
    <pubDate>#{Time.parse(update[1]).strftime("%a, %d %b %Y %H:%M:%S %z")}</pubDate>
    </item>
RSS
  end
    file.write "  </channel>\n</rss>"
end
