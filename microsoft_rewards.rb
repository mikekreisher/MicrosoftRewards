require 'io/console'
require 'open-uri'
require 'bundler/setup'
require 'optparse'

Bundler.require

options = {}
opt_parser = OptionParser.new do |opts|
  opts.on('-c n', '--config=n', 'Config Filename') do |f|
    options[:config_file] = f
  end

  opts.on('-d', '--skip-mobile', 'Skip Mobile',
          'Skip Mobile') do
    options[:skip_mobile] = true
  end

  opts.on('-m', '--skip-desktop', 'Skip Desktop',
          'Skip Desktop') do
    options[:skip_desktop] = true
  end

  opts.on('-s', '--skip-cards', 'Skip Cards',
          'Skip Cards') do
    options[:skip_cards] = true
  end

  opts.on('-h', '--help', 'Help',
          'Displays Help') do
    puts opts
    exit
  end
end

opt_parser.parse!

if options[:config_file].nil?
  print 'Enter config file: '
  options[:config_file] = gets.chomp
end

$username         = ''
$password         = ''
$approve_topics   = false
$errors           = false
$mobile_errors    = false
$browser          = ''
$two_factor       = ''
mobile            = false
search_count      = 30

if File.exist?(options[:config_file])
  config_file = File.open(options[:config_file], 'r')
  config_file.each do |line|
    split_line = line.chomp.split('=')
    unless split_line[1].nil?
      case split_line[0]
      when '[browser]'
        $browser = split_line[1].to_sym
      when '[username]'
        $username = split_line[1]
      when '[password]'
        $password = split_line[1]
      when '[approve_topics]'
        $approve_topics = split_line[1] == 'true'
      when '[2faemail]'
        $two_factor = split_line[1]
      end
    end
  end
  config_file.close
else
  print "Unable to find config file: #{options[:config_file]}...exiting\n"
  exit
end

def login(browser)
  begin
    login = browser.text_field :type => 'email'#, :name => 'login'
    pass = browser.text_field :type => 'password', :name => 'passwd'
    sign_in_button = browser.input :type => 'submit'

    if $username == ""
      puts "Username: "
      $username = STDIN.gets.chomp
    end
    login.when_present.set $username

    unless pass.visible?
      sign_in_button.click
    end

    pass = browser.text_field :type => 'password', :name => 'passwd'
    sign_in_button = browser.input :type => 'submit'

    if $password == ""
      puts "Password: "
      $password = STDIN.noecho {|i| i.gets}.chomp
    end
    pass.when_present.set $password

    sign_in_button.click
    browser.alert.when_present.ok if browser.alert.exists?

  end #while(login.exists? && pass.exists? && sign_in_button.exists?)
  if (browser.url =~ /https:\/\/account\.live\.com\/ar\/cancel\?ru=https:.*/)
    print "SECURITY CHECK\n"
    browser.radio(id: 'idYesOption').set
    browser.input(type: 'button', id: 'iLandingViewAction').when_present.click
    browser.input(type: 'button', id: 'iOptionViewAction').when_present.click
  end

  if ($two_factor != "")
    #obfuscated_2fa = $two_factor.gsub(/(..).*(@.*)/, '\1.*\2')
    #print obfuscated_2fa if browser.div(:text, /#{obfuscated_2fa}/).exists?
    #if browser.div(:text, /#{obfuscated_2fa}/).exists?
    #  tfa_parent = browser.div(:text, /#{obfuscated_2fa}/).parent
    #  tfa_parent = tfa_parent.parent until parent.tag == "div" and parent.class == "table-row"
    #  tfa_parent.click
    #end
    #puts "Waiting..."
    #STDIN.gets.chomp
    two_factor_email_input = browser.text_field :type => 'email'
    two_factor_button = browser.input :type => 'submit'

    two_factor_email_input.when_present.set $two_factor
    two_factor_button.click

    puts "Two Factor Authentication Code: "
    tfa_code = STDIN.gets.chomp

    two_factor_code_input = browser.text_field :type => "tel"
    two_factor_code_input.when_present.set tfa_code

    two_factor_submit = browser.input :type => 'submit'
    two_factor_submit.click
  end

  print "Logged in as #{$username}\n"
end

def search(search_count, browser)
  search_topics_url = 'https://soovle.com/top'
  topics_doc = []
  begin
    print "Gathering Searches...\n"
    web_searches = Nokogiri::HTML(open(search_topics_url))
    topics_doc = web_searches.search('div.letter .correction span').to_a
    topics     = topics_doc.sample(search_count).collect{|x| x.content}
    File.open('cached_topics.txt', 'w+') { |f| f.puts topics_doc }
  rescue OpenURI::HTTPError => e
    print "HTTPError attempting to read from cache\n"
    $errors = true
  rescue Net::ReadTimeout => e
    print "Could not reach #{search_topics_url} attempting to read from cache\n"
    #print "#{File.exist?('cached_topics.txt')}\n"

  rescue Exception => e
    print "#{e.class} - #{e.message}\n"
  ensure
    if topics_doc.empty? && File.exist?('cached_topics.txt')
      topics_doc = File.readlines('cached_topics.txt')
      topics     = topics_doc.sample(search_count).collect do |x|
        Nokogiri::HTML(x).search('span').first.content
      end
    else
      $errors = true
      #raise IOError, "Unable to reach #{search_topics_url}: #{e.message}\n"
    end
    topics.shuffle!
    print "Found #{topics.length} Search Topics\n"
  end

  if $approve_topics
    topics_approved = false
    while !topics_approved
      print "=============\nSEARCH TOPICS\n=============\n"
      topics.each_with_index do |topic, i|
        print "#{(i+1).to_s.rjust(2)}. #{topic}\n"
      end
      print "=============\n=============\n"
      puts "Do you approve these topics? (y|n):"
      if STDIN.gets.chomp.downcase == "y"
        topics_approved = true
      else
        topics_doc = File.readlines('cached_topics.txt')
        topics     = topics_doc.sample(search_count).collect do |x|
          Nokogiri::HTML(x).search('span').first.content
        end
        topics.shuffle!
      end
    end
  end

  begin
    topics.each_with_index do |topic, i|
      wait_time = 8 + Random.rand(11) # Random wait of at least 8 seconds
      print "#{(i+1).to_s.rjust(2)}. Searching for #{topic}...then waiting #{wait_time} seconds\n"
      browser.alert.when_present.ok if browser.alert.exists?
      browser.text_field(:id=>"sb_form_q").when_present.set(topic)
      browser.form(:id=>"sb_form").when_present.submit
      sleep wait_time
    end
    print "\n==================\nSEARCHES COMPLETED\n==================\n"
  rescue Watir::Exception => e
    print "\n*****\nERROR\n*****\n"
    print "There was an error performing the searches:\n#{e.message}\n"
    $errors = true
    raise Watir::Exception::WatirException, "Could not find form"
  rescue Watir::Exception::TimeoutException => e
    print "\n*****\nERROR\n*****\n"
    print "There was an error performing the searches:\n#{e.message}\n"
    $errors = true
    raise Watir::Exception::WatirException, "Timeout Occurred"
  end
end

def todo_list(browser, mobile, options)
  offer_cards = browser.links(class: 'offer-cta')
  offer_card_titles = offer_cards.collect {|o| o.div(class: 'offer-title-height').text unless o.div(class: 'offer-complete-card-button-background').exists? }
  searching_complete = false
  first_run = true

  if options[:skip_cards]
    print "Skipping Cards. Number Available: #{offer_card_titles.length}\n"
  else
    offer_card_titles.each do |offer_title|
      unless offer_title.nil? || offer_title.empty?
        offer_link = browser.div(:text, offer_title).parent.parent
        #offer_value = offer_link.span(class: 'card-button-line-height').text
        #print "- #{offer_title} - #{offer_value}\n"
        print "- #{offer_title}\n"
        offer_link.click

        browser.windows.last.use
        browser.windows.last.close if browser.windows.length > 1
        sleep 5
      end
    end
  end

  until searching_complete do
    sleep 5
    if mobile
      search_link = browser.link(text: "Mobile search")
      search_tile = search_link.parent.parent
      search_value_str = search_tile.p(:text, /.*points per search.*/).text
      pps = search_value_str.match(/.*(\d+) points per search.*/)[1].to_i

    else
      search_link = browser.link(text: "PC search")
      search_tile = search_link.parent.parent
      search_value_str = search_tile.p(:text, /.*points per search.*/).text
      pps = search_value_str.match(/.*(\d+) points per search.*/)[1].to_i
    end
    pps = 10 if pps == 0

    progress = search_tile.p(class: 'pointsDetail').text.match(/(\d+) \/ (\d+)/)
    current_credit = progress[1].to_i
    max_credit = progress[2].to_i

    browser.execute_script('arguments[0].scrollIntoView()', search_link)
    #search_link.click
    browser.goto 'https://www.bing.com'

    browser.windows.last.use
    if max_credit == current_credit
      searching_complete = true
      browser.windows.last.close if browser.windows.length > 1
    else
      print "Looks like we didn't get all the points last time...\n" unless first_run
      search((max_credit - current_credit) / pps, browser)
      browser.goto 'https://account.microsoft.com/rewards/pointsbreakdown'
      #browser.goto 'https://account.microsoft.com/rewards'
      first_run = false
    end

  end


end

unless options[:skip_mobile]
  print "\n=======================\nSTARTING REWARDS MOBILE\n=======================\n"
  print "Starting Browser\n"
  driver = Webdriver::UserAgent.driver(:browser => $browser, :agent => :android_phone, :orientation => :landscape)
  b = Watir::Browser.new driver
  b.window.resize_to(800, 1000)
  mobile = true
  b.goto 'login.live.com'

  login(b)

  b.goto 'https://account.microsoft.com/rewards'

  b.link(id: 'signinhero').click if b.link(id: 'signinhero').exists?

  b.goto 'https://account.microsoft.com/rewards/pointsbreakdown'

  todo_list(b, mobile, options)

  b.refresh

  begin
    #goal_elem = b.link(id: 'goal').parent.parent
    #goal_title = goal_elem.link(id: 'goal').text
    b.goto 'https://account.microsoft.com/rewards'
    sleep(5)
    print "\n======\nSTATUS\n======\n"
    info_divs = b.divs(class: 'info')
    available_points = info_divs[0].p(class: 'number').text
    lifetime_points = info_divs[0].p(class: 'description').text
    streak_count = info_divs[1].p(class: 'number').text
    bonus_gift = info_divs[1].p(class: 'description').text

    print "#{available_points} Credits Available\n"
    print "#{lifetime_points}\n"
    print "#{streak_count} Streak Count\n"
    print "#{bonus_gift}\n"

    goal_elem = b.div(class: 'cardContainer')
    goal_title = goal_elem.h3.text
    print "\n#{goal_title}\n"
    progress_str = goal_elem.p(class: 'c-subheading-4').text
    print "#{progress_str}\n"
    progress = progress_str.gsub!(/,/, '').match(/(\d+) \/ (\d+)/)
    percent_complete = ((progress[1].to_f / progress[2].to_f) * 100).floor
    print "#{percent_complete}% Complete"

  rescue Exception => e
    print "\nUnable to find goal: #{e.message}\n"
  end

  print "\n===============\nMOBILE COMPLETE\n===============\n"
  b.close
end
print "\nCompleted mobile run for #{$username} at #{Time.now} #{$errors ? 'with errors' : ''}\n"

unless options[:skip_desktop]
  print "\n========================\nSTARTING REWARDS DESKTOP\n========================\n"
  print "Starting Browser\n"
  b = Watir::Browser.new $browser
  mobile = false
  b.goto 'login.live.com'

  login(b)

  b.goto 'https://account.microsoft.com/rewards'

  b.link(id: 'signinhero').click if b.link(id: 'signinhero').exists?

  b.goto 'https://account.microsoft.com/rewards/pointsbreakdown'

  todo_list(b, mobile, options)

  b.refresh

  begin
    b.goto 'https://account.microsoft.com/rewards'
    sleep(5)
    print "\n======\nSTATUS\n======\n"
    info_divs = b.divs(class: 'info')
    available_points = info_divs[0].p(class: 'number').text
    lifetime_points = info_divs[0].p(class: 'description').text
    streak_count = info_divs[1].p(class: 'number').text
    bonus_gift = info_divs[1].p(class: 'description').text

    print "#{available_points} Credits Available\n"
    print "#{lifetime_points}\n"
    print "#{streak_count} Streak Count\n"
    print "#{bonus_gift}\n"
    goal_elem = b.div(class: 'cardContainer')
    goal_title = goal_elem.h3.text
    print "\n#{goal_title}\n"
    #progress_str = goal_elem.div(:text, /\d+,?\d+ of \d+,?\d+/).text
    progress_str = goal_elem.p(class: 'c-subheading-4').text
    print "#{progress_str}\n"
    progress = progress_str.gsub!(/,/, '').match(/(\d+) \/ (\d+)/)
    percent_complete = ((progress[1].to_f / progress[2].to_f) * 100).floor
    print "#{percent_complete}% Complete"

  rescue Exception => e
    print "\nUnable to find goal: #{e.message}\n"
  end

  print "\n================\nDESKTOP COMPLETE\n================\n"
end
print "\nCompleted run for #{$username} at #{Time.now} #{$errors ? 'with errors' : ''}\n"


b.close