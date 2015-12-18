require 'rubygems'
require 'mechanize'
require 'pathname'
require 'fileutils'
require 'nokogiri'
require 'dotenv'

# Load dotenv
Dotenv.load

a = Mechanize.new { |agent|
  # Sky refreshes after login
  agent.follow_meta_refresh = true
}


puts "Fetching login page..."
a.get('http://www.tv5monde.com/pro/lg-gb/Bienvenue-sur-TV5MONDE-PRO') do |home_page|
  puts "Logging in.."
  my_page = home_page.form_with(:class => 'flog clearfix') do |form|
    form['login_mail']  = ENV['TV5_LOGIN']
    form['login_pwd'] = ENV['TV5_PASSWORD']
  end.submit

  # Get files
  files = a.get("http://www.tv5monde.com/pro/frg-5/lg-gb/Programs/Europe/Mensuels").body
  @main_noko = Nokogiri::HTML files rescue nil
  @main_noko.css('ul.bloc_corefiles > li').map do |e|

    if e.css('a').text =~ /XLS Version/i
      file_name = e.css("a")[0]["title"][/: (.*?)$/, 1].strip
      next if File.exist?('/nonametv/channels/tv5monde.org/' + file_name)

      File.open('/nonametv/channels/tv5monde.org/' + file_name, 'wb'){|f| f << a.get("http://www.tv5monde.com" + e.css("a")[0]["href"]).body}
      puts "Added #{file_name} to tv5monde.org"
    end

  end

end
