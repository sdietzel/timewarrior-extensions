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

  unless e.has_key? 'tags'
    puts "WARNING: Untagged entries on #{date}".red
  else
    e['tags'].each do |tag|
      tags.add(tag)
    
      days[date][tag] = {'duration' => 0, 'description' => []} unless days[date].has_key? tag
  
      days[date][tag]['duration'] += e['duration'] / e['tags'].size
      days[date][tag]['description'] += [e['annotation']] if e.has_key? 'annotation'
    end
  end
end

totals = tags.map{ |t| [t, 0] }.to_h
expected = 0

tags = SPECIAL_TAGS + (tags - Set.new(SPECIAL_TAGS)).to_a

puts '----- ' + report_start.strftime('%^B %Y') + ' -----'
puts

puts "Date   " + tags.map{ |t| '%10s' % t }.join(' ') + "  Description"

(report_start..report_end).each do |day|
  expected += HOURS_PER_DAY if is_workday? day
  
  daystr = is_workday?(day) ? day.strftime('%d %a').green : day.strftime('%d %a')
  
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
      
      d
    else
      0
    end
  end.map do |e|
    if e > 0
      '%10.2f' % e
    else
      '         -'
    end
  end.join(' ')
  
  str += '  ' + entries.map{ |t, e| "#{t}: " + e['description'].join(', ') }.join(', ')
  
  puts str
end

puts

sum = totals.map{ |t, d| d }.reduce(:+)
productive = totals.map do |t, d|
  if SPECIAL_TAGS.include? t
    0
  else
    d
  end
end.reduce(:+)

puts 'TOTAL  ' + totals.map{ |t, d| '%10.2f' % d }.join(' ')
puts '       ' + totals.map{ |t, d| '%9.0f%%' % (d / productive * 100) }.join(' ')

puts

puts "Expected: %3.1f hours" % expected
puts "Actual:   %3.1f hours" % sum
puts "Overtime: %3.1f hours" % (sum - expected)