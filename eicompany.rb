#!/usr/bin/env ruby

require 'json'
require 'date'
require 'set'
require 'holidays'
require 'colorize'

HOURS_PER_DAY = 8
SPECIAL_TAGS = %w[U K].freeze
UNKNOWN = '?????'.freeze

require 'holidays/core_extensions/date'
class Date
  include Holidays::CoreExtensions::Date
end

def round_duration(duration)
  (duration * 4).round.to_f / 4.0
end

def workday?(day)
  !(day.holiday?(:de, :de_be) or day.saturday? or day.sunday?)
end

def pad(tag, value)
  l = [tag.size + 1, 5].max
  "%#{l}s" % value
end

report = ARGF.read
config, entries = report.split("\n\n")

report_start = if (m = config.match(/temp.report.start: (?<date>.+)/))
                 DateTime.parse(m[:date]).to_time.getlocal.to_date
               else
                 Date.today
               end

report_end = if (m = config.match(/temp.report.end: (?<date>.+)/))
               DateTime.parse(m[:date]).to_time.getlocal.to_date - 1
             else
               Date.today
             end

entries = JSON.parse(entries)

active_tags = []

entries.map! do |e|
  e['tags'].map!(&:upcase) if e.key? 'tags'

  e['start'] = DateTime.parse(e['start'])
  if e.key? 'end'
    e['end'] = DateTime.parse(e['end'])
  else
    e['end'] = DateTime.now
    active_tags = e['tags'] if e.key? 'tags'
  end


  e['duration'] = (e['end'] - e['start']) * 24.0

  e
end

tags = Set[]
days = {}

entries.each do |e|
  date = e['start'].to_time.getlocal.to_date

  days[date] = {} unless days.key? date

  e['tags'] = [UNKNOWN] unless e.key? 'tags'

  e['tags'].each do |tag|
    tags.add(tag)

    days[date][tag] = { 'duration' => 0, 'description' => [] } unless days[date].key? tag

    days[date][tag]['duration'] += e['duration'] / e['tags'].size
    days[date][tag]['description'] += [e['annotation']] if e.key? 'annotation'
  end
end

tags = SPECIAL_TAGS + (tags - Set.new(SPECIAL_TAGS)).to_a.sort
totals = tags.map { |t| [t, 0] }.to_h

puts 'Date     '.underline + ' ' +
     (tags.map do |t|
       if active_tags.include? t
         pad(t, t).green.underline
       else
         pad(t, t).underline
       end
     end.join(' ')) + '  ' +
     'Description'.underline

(report_start..report_end).each do |day|
  str = day.strftime('%m/%d %a')
  str = str.light_black unless workday?(day)
  str = str.blue if day == Date.today

  unless days.key? day
    puts str
    next
  end

  entries = days[day]

  str += ' '

  str += tags.map do |t|
    if entries.key? t
      d = round_duration(entries[t]['duration'])
      totals[t] += d

      s = pad(t, '%.2f' % d)

      if t == UNKNOWN
        s.yellow
      elsif day == Date.today and active_tags.include? t
        s.green
      else
        s
      end
    else
      pad(t, '-')
    end
  end.join(' ')

  str += '  ' + entries.reject { |k, _| SPECIAL_TAGS.include? k }
                       .map do |t, e|
                         if e['description'].empty?
                           t.yellow
                         else
                           "#{t}: " + e['description'].uniq.join(', ')
                         end
                       end.join(' / ')

  puts str
end

expected = (report_start..report_end).select { |d| workday? d }.size * HOURS_PER_DAY

sum = totals.values.reduce(:+)
productive = totals.reject { |k, _| SPECIAL_TAGS.include? k }.values.reduce(:+)

puts '          ' + totals.map { |t, d| pad(t, '%.2f' % d) }.join(' ').bold
puts '          ' + (totals.map do |t, d|
  if !SPECIAL_TAGS.include? t and productive > 0
    pad(t, format('%.0f%%', (d / productive * 100)))
  else
    pad(t, '')
  end
end.join(' ')).cyan

puts

puts 'Expected: %6.1f hours' % expected
if sum
  puts 'Actual:   %6.1f hours' % sum
  puts format('Overtime: %6.1f hours', (sum - expected))
end
