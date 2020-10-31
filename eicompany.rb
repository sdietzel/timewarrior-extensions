#!/usr/bin/env ruby

require 'json'
require 'date'
require 'set'
require 'holidays'
require 'colorize'

HOURS_PER_DAY = 8

SPECIAL_TAGS = ['U', 'K']

require 'holidays/core_extensions/date'
class Date
  include Holidays::CoreExtensions::Date
end

def round_duration(duration)
  (duration * 4).round.to_f / 4.0
end

def is_workday?(day)
  !(day.holiday?(:de, :de_be) or day.saturday? or day.sunday?)
end

def pad(tag, value)
  l = [tag.size + 1, 5].max
  "%#{l}s" % value
end

report = ARGF.read
config, entries = report.split("\n\n")

report_start = if m = config.match(/temp.report.start: (?<date>.+)/)
  DateTime.parse(m[:date]).to_time.getlocal.to_date
else
  Date.today
end

report_end = if m = config.match(/temp.report.end: (?<date>.+)/)
  DateTime.parse(m[:date]).to_time.getlocal.to_date
else
  Date.today
end

entries = JSON.parse(entries)

entries.map! do |e|
  e['start'] = DateTime.parse(e['start'])
  e['end'] = DateTime.parse(e['end'])
  
  e['tags'].map! { |t| t.upcase } if e.has_key? 'tags'
  
  e['duration'] = (e['end'] - e['start']) * 24.0
  
  e
end

tags = Set[]
days = {}

entries.each do |e|
  date = e['start'].to_time.getlocal.to_date
  
  days[date] = {} unless days.has_key? date

  if e.has_key? 'tags'
    e['tags'].each do |tag|
      tags.add(tag)
    
      days[date][tag] = {'duration' => 0, 'description' => []} unless days[date].has_key? tag
  
      days[date][tag]['duration'] += e['duration'] / e['tags'].size
      days[date][tag]['description'] += [e['annotation']] if e.has_key? 'annotation'
    end
  end
end

expected = 0

tags = SPECIAL_TAGS + (tags - Set.new(SPECIAL_TAGS)).to_a
totals = tags.map{ |t| [t, 0] }.to_h

puts "Date     ".underline + ' ' + tags.map{ |t| pad(t, t).underline }.join(' ') + '  ' + 'Description'.underline

(report_start..report_end).each do |day|
  expected += HOURS_PER_DAY if is_workday? day
  
  daystr = is_workday?(day) ? day.strftime('%m/%d %a') : day.strftime('%m/%d %a').light_black
  
  unless days.has_key? day
    puts daystr
    next
  end
  
  entries = days[day]
  
  str = daystr + ' '
  
  str += tags.map do |t|
    if entries.has_key? t
      d = round_duration(entries[t]['duration'])
      totals[t] += d
      
      pad(t, '%.2f' % d)
    else
      pad(t, '-')
    end
  end.join(' ')
  
  str += '  ' + entries.reject{ |k, _| SPECIAL_TAGS.include? k }.map{ |t, e| "#{t}: " + e['description'].join(', ') }.join(', ')
  
  unless entries.size > 0
    str += "WARNING: No tags used!".red
  end
  
  puts str
end

sum = totals.map{ |t, d| d }.reduce(:+)
productive = totals.reject{ |k, _| SPECIAL_TAGS.include? k }.values.reduce(:+)

puts '          ' + totals.map{ |t, d| pad(t, '%.2f' % d) }.join(' ').bold
puts '          ' + (totals.map do |t, d|
  unless SPECIAL_TAGS.include? t
    pad(t, '%.0f%%' % (d / productive * 100))
  else
    pad(t, '')
  end
end.join(' ')).cyan

puts

puts "Expected: %6.1f hours" % expected
if sum
  puts "Actual:   %6.1f hours" % sum
  puts "Overtime: %6.1f hours" % (sum - expected)
end