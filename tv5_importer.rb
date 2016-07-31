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
  files = a.get("http://www.tv5monde.com/pro/frg-5/lg-gb/Programs/Europe/Hebdomadaires-Complements").body
  @main_noko = Nokogiri::HTML files rescue nil
  @results = @main_noko.css('li.file-zip').map

  puts "Found #{@results.count} xls files.."

  # Each
  @results.each do |e|
    file_name = e.css("a")[0]["title"][/: (.*?)$/, 1].strip
    next if File.exist?('/home/jnylen/content/channels/tv5monde.org/' + file_name)

    puts "Fetching http://www.tv5monde.com" + e.css("a")[0]["href"]

    # Download file
    file = a.get("http://www.tv5monde.com" + e.css("a")[0]["href"])

    if file.body.strip == "getUserData_error_content"
      puts "Error: Couldn't fetch #{file_name}."
    else
      File.open('/home/jnylen/content/channels/tv5monde.org/' + file_name, 'wb'){|f| f << file.body}
      puts "Added #{file_name} to tv5monde.org"
    end



  end

end
