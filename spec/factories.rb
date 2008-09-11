# Trying out factory girl. Check out the documentation here.
# http://github.com/thoughtbot/factory_girl/tree/master

Factory.define :podcast do |p|
  p.title    'Podcast'
  p.site     'http://podcasts.example.com'
  p.feed_url 'http://podcasts.example.com/feed.xml'
end

Factory.define :episode do |e|
  e.association  :podcast, :factory => :podcast
  e.summary      'This is the first episode of a show! w0000t'
  e.title        'Episode One'
  e.published_at Time.now
end

Factory.sequence :login do |n|
  "tester#{n}"
end
Factory.sequence :email do |n|
  "tester#{n}@podcasts.example.com"
end

Factory.define :user do |u|
  u.login    { Factory.next :login }
  u.email    { Factory.next :email }
  u.password 'password'
  u.salt     'NaCl'
end

Factory.define :admin_user, :class => User do |u|
  u.login    'admin'
  u.email    'admin@podcasts.example.com'
  u.password 'password'
  u.salt     'NaCl'

  u.admin true
end

Factory.define :podcast_comment, :class => Comment do |c|
  c.association :commenter, :factory => :user
  c.association :commentable, :factory => :podcast
end

Factory.define :episode_comment, :class => Comment do |c|
  c.association :commenter, :factory => :user
  c.association :commentable, :factory => :podcast
end

