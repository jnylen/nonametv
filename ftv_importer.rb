require 'rubygems'
require 'pathname'
require 'fileutils'
require 'nokogiri'
require 'mechanize'

a = Mechanize.new { |agent|
  # Sky refreshes after login
  agent.follow_meta_refresh = true
}

# Channels
channels = [
  { :xmltvid => "ftv.com", :info => "fashiontv_", info2: "HotBird" },
  { :xmltvid => "hd.ftv.com", :info => "fashiontvHD_", info2: "HotBird" },
]

page = a.get('http://www.fashiontv.com/epg').body
@main_noko = Nokogiri::HTML page rescue nil
@main_noko.css('div#articlecontent > ul > li > a').map do |e|
  url = e["href"]
  file_name = Pathname.new(url).basename.to_s
  next if !url.end_with? "xlsx"

  # Only add files that is this year or next.
  if url =~ /#{Date.today.year}/ or url =~ /#{Date.today.year + 1}/
    channels.each do |c|
      next if file_name !~ /#{c[:info]}/i or file_name !~ /#{c[:info2]}/i or File.exist?('/nonametv/channels/' + c[:xmltvid] + '/' + file_name)

      File.open('/nonametv/channels/' + c[:xmltvid] + '/' + file_name, 'wb'){|f| f << a.get(url).body}
      puts "Added #{file_name} to #{c[:xmltvid]}"
    end
  end
end
