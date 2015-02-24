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

# Copy files to these channels
def copy_to_channels(file_name)
    # Channels
    channels = [
    { :xmltvid => "13thstreet.de", :info => "13TH STREET" }, { :xmltvid => "hd.13thstreet.de", :info => "13TH STREET HD" },
    { :xmltvid => "ae-tv.de", :info => "A&E" }, { :xmltvid => "beate-uhse.tv", :info => "BEATE-UHSE.TV" },
    { :xmltvid => "1.bluemovie.de", :info => "BLUE MOVIE 1" }, { :xmltvid => "2.bluemovie.de", :info => "BLUE MOVIE 2" },
    { :xmltvid => "3.bluemovie.de", :info => "BLUE MOVIE 3" }, { :xmltvid => "hd.bluemovie.de", :info => "BLUE MOVIE HD" },
    { :xmltvid => "foxchannel.de", :info => "FOX" }, { :xmltvid => "hd.foxchannel.de", :info => "FOX HD" },
    { :xmltvid => "goldstar-tv.de", :info => "GOLDSTAR TV" }, { :xmltvid => "heimatkanal.de", :info => "HEIMATKANAL" },
    { :xmltvid => "hd.historytv.de", :info => "HISTORY HD" }, { :xmltvid => "junior.tv", :info => "JUNIOR" },
    { :xmltvid => "jukebox-tv.de", :info => "JUKEBOX" }, { :xmltvid => "kinowelt.tv", :info => "KINOWELT TV" },
    { :xmltvid => "motorvision.de", :info => "MOTORVISION" }, { :xmltvid => "wild.natgeo.de", :info => "NATIONAL GEOGRAPHIC WILD" },
    { :xmltvid => "wildhd.natgeo.de", :info => "NATIONAL GEOGRAPHIC WILD HD" }, { :xmltvid => "natgeo.de", :info => "NATIONAL GEOGRAPHIC" },
    { :xmltvid => "hd.natgeo.de", :info => "NATIONAL GEOGRAPHIC HD" }, { :xmltvid => "passion.de", :info => "PASSION" },
    { :xmltvid => "romance-tv.de", :info => "ROMANCE TV" }, { :xmltvid => "crime.rtl.de", :info => "RTL Crime" },
    { :xmltvid => "crimehd.rtl.de", :info => "RTL Crime HD" }, { :xmltvid => "living.rtl.de", :info => "RTL LIVING" },
    { :xmltvid => "discovery.de", :info => "Discovery Channel" }, { :xmltvid => "hd.discovery.de", :info => "Discovery Channel HD" },
    { :xmltvid => "classica.de", :info => "CLASSICA" },

    { :xmltvid => "3d.sky.de", :info => "SKY HD-3D" }, { :xmltvid => "action.sky.de", :info => "Sky Action" },
    { :xmltvid => "actionhd.sky.de", :info => "Sky Action HD" }, { :xmltvid => "atlantic.sky.de", :info => "SKY ATLANTIC" },
    { :xmltvid => "atlantichd.sky.de", :info => "SKY ATLANTIC HD" }, { :xmltvid => "cinema.sky.de", :info => "SKY CINEMA" },
    { :xmltvid => "cinemahd.sky.de", :info => "SKY CINEMA HD" }, { :xmltvid => "p1.cinema.sky.de", :info => "Sky Cinema +1" },
    { :xmltvid => "p1hd.cinema.sky.de", :info => "Sky Cinema +1 HD" }, { :xmltvid => "p24.cinema.sky.de", :info => "Sky Cinema +24" },
    { :xmltvid => "p24hd.cinema.sky.de", :info => "Sky Cinema +24 HD" }, { :xmltvid => "comedy.sky.de", :info => "SKY COMEDY" },
    { :xmltvid => "emotion.sky.de", :info => "SKY EMOTION" }, { :xmltvid => "hits.sky.de", :info => "SKY HITS" },
    { :xmltvid => "hitshd.sky.de", :info => "SKY HITS HD" }, { :xmltvid => "krimi.sky.de", :info => "SKY KRIMI" },
    { :xmltvid => "nostalgie.sky.de", :info => "SKY NOSTALGIE" }, { :xmltvid => "select.sky.de", :info => "Sky Select" },
    { :xmltvid => "selecthd.sky.de", :info => "SKY SELECT HD" }, { :xmltvid => "bundesliga1.sky.de", :info => "Sky Bundesliga 1" },
    { :xmltvid => "bundesligahd1.sky.de", :info => "Sky Bundesliga HD 1" }, { :xmltvid => "sport1.sky.de", :info => "Sky Sport 1" },
    { :xmltvid => "sport2.sky.de", :info => "Sky Sport 2" }, { :xmltvid => "sporthd1.sky.de", :info => "Sky Sport HD 1" },
    { :xmltvid => "sporthd2.sky.de", :info => "Sky Sport HD 2" }, { :xmltvid => "sportaustria.sky.de", :info => "Sky Sport Austria" },
    { :xmltvid => "sportnews.sky.de", :info => "SKY SPORT NEWS" }, { :xmltvid => "sportnewshd.sky.de", :info => "SKY SPORT NEWS HD" },

    { :xmltvid => "spiegel-geschichte.tv", :info => "SPIEGEL GESCHICHTE" }, { :xmltvid => "hd.spiegel-geschichte.tv", :info => "SPIEGEL GESCHICHTE HD" },
    { :xmltvid => "sportdigital.tv", :info => "SPORTDIGITAL.TV" }, { :xmltvid => "syfy.de", :info => "SCI FI" },
    { :xmltvid => "hd.syfy.de", :info => "SCI FI HD" }, { :xmltvid => "tnt-film.de", :info => "TNT FILM" },
    { :xmltvid => "hd.tnt-glitz.tv", :info => "TNT GLITZ HD" },
    { :xmltvid => "tnt-serie.de", :info => "TNT SERIE" }, { :xmltvid => "hd.tnt-serie.de", :info => "TNT SERIE HD" },
    { :xmltvid => "universalchannel.de", :info => "UNIVERSAL CHANNEL HD" },
    ]

    channels.each do |c|
        # Each channel (create dir if it doesn't exist)
        FileUtils::mkdir_p '/nonametv/channels/' + c[:xmltvid] if !File.directory?('/nonametv/channels/' + c[:xmltvid])
        file_basename = Pathname.new(file_name).basename.to_s

        # Remove if it already exists
        FileUtils.rm('/nonametv/channels/' + c[:xmltvid] + '/' + file_basename) if File.exist?('/nonametv/channels/' + c[:xmltvid] + '/' + file_basename)

        #puts "Cleaning up #{file_basename} for #{c[:xmltvid]}"
        # We are going to remove all data that isn't for that specified channel.
        io = File.open(file_name, 'r')
        doc = Nokogiri::XML(io)
        io.close

        doc.xpath('//programmElement').each do |node|
            if node.xpath('./@service').to_s != c[:info]
                node.remove
            end
        end

        File.open('/nonametv/channels/' + c[:xmltvid] + '/' + file_basename, 'w') { |f| f.print(doc.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)) }

        # Verbose
        puts "Cleaned up and added #{file_basename} to #{c[:xmltvid]}"
    end
end

puts "Fetching login page..."
a.get('http://info.sky.de/inhalt/de/programm_info_presseexport_start.jsp') do |home_page|
  puts "Logging in.."
  my_page = home_page.form_with(:name => 'presscustomer.boundary.loginForm') do |form|
    form['login']  = ENV['LOGIN']
    form['password'] = ENV['PASSWORD']
  end.submit

  # Safety first - Grab all XML links
  begin
    xml_files = my_page.links_with(:href => /_xml\.gz/, :text => 'Download')

    puts "Found #{xml_files.count} XML files"

    xml_files.each do |link|
      # Download files to the folder
      file_name = Pathname.new(link.href).basename.to_s.gsub(/\.gz$/, ".xml").gsub(/(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)_xml/, "").gsub(/(\d\d)(\d\d)_xml/, "")

      # If it exists, check if it differs otherwise just add it already
      if File.exist?('/nonametv/skyde/' + file_name)
        File.open('/tmp/' + file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }

        # Check if it's changed or not
        if !FileUtils.compare_file('/tmp/' + file_name, '/nonametv/skyde/' + file_name)
          FileUtils.rm('/nonametv/skyde/' + file_name)
          FileUtils.mv('/tmp/' + file_name, '/nonametv/skyde/' + file_name)

          puts "Updated #{file_name}"

          # Channels
          copy_to_channels('/nonametv/skyde/' + file_name)
        else
          FileUtils.rm('/tmp/' + file_name)
          puts "Not changed #{file_name}"
        end
      else
        File.open('/nonametv/skyde/' + file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }
        puts "Downloaded #{file_name}"

        # Channels
        copy_to_channels('/nonametv/skyde/' + file_name)
      end

      #File.open(file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }
    end
  rescue Exception => e
    puts "Couldn't find any xml files. (#{e.message})"
  end

  # Log out (sky only allows 1 logged in user per time. It logs you out after a few mins.)
  begin
    log_out = my_page.link_with(:text => 'Logout').click
    puts "Logged out successfully."
  rescue Exception => e
    puts "Couldn't log out successfully. (#{e.message})"
  end
end