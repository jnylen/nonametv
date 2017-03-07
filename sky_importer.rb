require 'rubygems'
require 'mechanize'
require 'pathname'
require 'fileutils'
require 'nokogiri'
require 'dotenv'

class String
  def squish
    dup.squish!
  end
  def squish!
    gsub!(/\A[[:space:]]+/, '')
    gsub!(/[[:space:]]+\z/, '')
    gsub!(/[[:space:]]+/, ' ')
    self
  end
end


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
    { :xmltvid => "13thstreet.de", :info => "13TH STREET" },
    { :xmltvid => "ae-tv.de", :info => "A&E" }, { :xmltvid => "beate-uhse.tv", :info => "BEATE-UHSE.TV" },
    { :xmltvid => "1.bluemovie.de", :info => "BLUE MOVIE 1" }, { :xmltvid => "2.bluemovie.de", :info => "BLUE MOVIE 2" },
    { :xmltvid => "3.bluemovie.de", :info => "BLUE MOVIE 3" }, { :xmltvid => "hd.bluemovie.de", :info => "BLUE MOVIE HD" },
    { :xmltvid => "foxchannel.de", :info => "FOX" },
    { :xmltvid => "goldstar-tv.de", :info => "GOLDSTAR TV" }, { :xmltvid => "heimatkanal.de", :info => "HEIMATKANAL" },
    { :xmltvid => "hd.historytv.de", :info => "HISTORY HD" }, { :xmltvid => "junior.tv", :info => "JUNIOR" },
    { :xmltvid => "jukebox-tv.de", :info => "JUKEBOX" }, { :xmltvid => "kinowelt.tv", :info => "KINOWELT TV" },
    { :xmltvid => "motorvision.de", :info => "MOTORVISION" }, { :xmltvid => "wild.natgeo.de", :info => "NATIONAL GEOGRAPHIC WILD" },
    { :xmltvid => "natgeo.de", :info => "NATIONAL GEOGRAPHIC" }, { :xmltvid => "passion.de", :info => "PASSION" },
    { :xmltvid => "romance-tv.de", :info => "ROMANCE TV" }, { :xmltvid => "crime.rtl.de", :info => "RTL Crime" }, { :xmltvid => "living.rtl.de", :info => "RTL LIVING" },
    { :xmltvid => "discovery.de", :info => "Discovery Channel" }, { :xmltvid => "classica.de", :info => "CLASSICA" },

    { :xmltvid => "3d.sky.de", :info => "SKY HD-3D" }, { :xmltvid => "action.sky.de", :info => "Sky Action" },
    { :xmltvid => "action.sky.de", :info => "Sky Cinema Action" },
    { :xmltvid => "atlantic.sky.de", :info => "SKY ATLANTIC" },
    { :xmltvid => "atlanticp1.sky.de", :info => "SKY ATLANTIC +1 HD" }, { :xmltvid => "arts.sky.de", :info => "SKY ARTS HD" },
    { :xmltvid => "cinema.sky.de", :info => "SKY CINEMA" },
    { :xmltvid => "p1.cinema.sky.de", :info => "Sky Cinema +1" }, { :xmltvid => "p24.cinema.sky.de", :info => "Sky Cinema +24" },
    { :xmltvid => "family.cinema.sky.de", :info => "SKY CINEMA FAMILY" },{ :xmltvid => "comedy.sky.de", :info => "SKY Cinema COMEDY" },
    { :xmltvid => "emotion.sky.de", :info => "SKY Cinema EMOTION" }, { :xmltvid => "hits.sky.de", :info => "Sky Cinema Hits" },
    { :xmltvid => "krimi.sky.de", :info => "SKY KRIMI" },
    { :xmltvid => "nostalgie.sky.de", :info => "SKY Cinema NOSTALGIE" }, { :xmltvid => "select.sky.de", :info => "Sky Select" },
    { :xmltvid => "sportaustria.sky.de", :info => "SKY SPORT AUSTRIA" },
    { :xmltvid => "sportnews.sky.de", :info => "SKY SPORT NEWS" },

    { :xmltvid => "bundesliga1.sky.de", :info => "Sky Sport Bundesliga 1" }, { :xmltvid => "bundesliga2.sky.de", :info => "Sky Sport Bundesliga 2" },
    { :xmltvid => "bundesliga3.sky.de", :info => "Sky Sport Bundesliga 3" }, { :xmltvid => "bundesliga4.sky.de", :info => "Sky Sport Bundesliga 4" },
    { :xmltvid => "bundesliga5.sky.de", :info => "Sky Sport Bundesliga 5" }, { :xmltvid => "bundesliga6.sky.de", :info => "Sky Sport Bundesliga 6" },
    { :xmltvid => "bundesliga7.sky.de", :info => "Sky Sport Bundesliga 7" }, { :xmltvid => "bundesliga8.sky.de", :info => "Sky Sport Bundesliga 8" },
    { :xmltvid => "bundesliga9.sky.de", :info => "Sky Sport Bundesliga 9" }, { :xmltvid => "bundesliga10.sky.de", :info => "Sky Sport Bundesliga 10" },

    { :xmltvid => "bundesligauhd.sky.de", :info => "Sky Bundesliga UHD" },

    { :xmltvid => "sport1.sky.de", :info => "Sky Sport 1" }, { :xmltvid => "sport2.sky.de", :info => "Sky Sport 2" },
    { :xmltvid => "sport3.sky.de", :info => "Sky Sport 3" }, { :xmltvid => "sport4.sky.de", :info => "Sky Sport 4" },
    { :xmltvid => "sport5.sky.de", :info => "Sky Sport 5" }, { :xmltvid => "sport6.sky.de", :info => "Sky Sport 6" },
    { :xmltvid => "sport7.sky.de", :info => "Sky Sport 7" }, { :xmltvid => "sport8.sky.de", :info => "Sky Sport 8" },
    { :xmltvid => "sport9.sky.de", :info => "Sky Sport 9" }, { :xmltvid => "sport10.sky.de", :info => "Sky Sport 10" },
    { :xmltvid => "sport11.sky.de", :info => "Sky Sport 11" },

    { :xmltvid => "sportuhd.sky.de", :info => "Sky Sport UHD" },

    { :xmltvid => "eins.sky.de", :info => "SKY 1" },

    { :xmltvid => "spiegel-geschichte.tv", :info => "SPIEGEL GESCHICHTE" },
    { :xmltvid => "sportdigital.tv", :info => "SPORTDIGITAL.TV" }, { :xmltvid => "syfy.de", :info => "SCI FI" },
    { :xmltvid => "tnt-film.de", :info => "TNT FILM" },
    { :xmltvid => "hd.tnt-glitz.tv", :info => "TNT COMEDY HD" },
    { :xmltvid => "tnt-serie.de", :info => "TNT SERIE" },
    { :xmltvid => "universalchannel.de", :info => "UNIVERSAL CHANNEL HD" },

    { :xmltvid => "boomerangtv.de", :info => "BOOMERANG" },
    { :xmltvid => "cartoonnetwork.de", :info => "CARTOON NETWORK" },
    { :xmltvid => "de.eonline.com", :info => "E! ENTERTAINMENT HD" }

    ]

    channels.each do |c|
        # Each channel (create dir if it doesn't exist)
        FileUtils::mkdir_p '/content/channels/' + c[:xmltvid] if !File.directory?('/content/channels/' + c[:xmltvid])
        file_basename = Pathname.new(file_name).basename.to_s

        # Remove if it already exists
        FileUtils.rm('/content/channels/' + c[:xmltvid] + '/' + file_basename) if File.exist?('/content/channels/' + c[:xmltvid] + '/' + file_basename)

        #puts "Cleaning up #{file_basename} for #{c[:xmltvid]}"
        # We are going to remove all data that isn't for that specified channel.
        io = File.open(file_name, 'r')
        doc = Nokogiri::XML(io)
        io.close

        doc.xpath('//programmElement').each do |node|
            if node.xpath('./@service').to_s.strip.downcase != c[:info].downcase.strip
                node.remove
            end
        end

        # File content
        content = doc.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML).squish!
        #content = content.gsub(/^\s+\s+\n$/, "")

        File.open('/content/channels/' + c[:xmltvid] + '/' + file_basename, 'w') { |f| f.print(content) }

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
      if File.exist?('/content/skyde/' + file_name)
        File.open('/tmp/' + file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }

        # Check if it's changed or not
        if !FileUtils.compare_file('/tmp/' + file_name, '/content/skyde/' + file_name)
          FileUtils.rm('/content/skyde/' + file_name)
          FileUtils.mv('/tmp/' + file_name, '/content/skyde/' + file_name)

          puts "Updated #{file_name}"

          # Channels
          copy_to_channels('/content/skyde/' + file_name)
        else
          FileUtils.rm('/tmp/' + file_name)
          puts "Not changed #{file_name}"
        end
      else
        File.open('/content/skyde/' + file_name, 'wb'){ |f| f << Zlib::GzipReader.new(StringIO.new(a.get('http://info.sky.de' + link.href).body.to_s)).read }
        puts "Downloaded #{file_name}"

        # Channels
        copy_to_channels('/content/skyde/' + file_name)
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

puts "Cleaning up the SKYDE folder.."
Dir.foreach('/content/skyde') do |item|
  next if item == '.' or item == '..'

  cur_week = Time.now.strftime('%W').to_i
  cur_year = Time.now.year.to_i

  if result = item.match(/_(\d\d)_(\d\d\d\d)/)
    week, year = result.captures

    if (week.to_i < (cur_week-1)) or (year.to_i < cur_year-1)
      FileUtils.rm('/content/skyde/' + item)
      puts "Removed #{item}"
    end
  end
end
