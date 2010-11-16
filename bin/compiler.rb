# Parser takes a string and creates a parser out of it.
# 
# Definition Example:
#     start={option_a}|{option_b}|/c/
#     option_a=/a/
#     option_b={option_b_regex}*
#     option_b_regex=/b/
#
# Matches: "a", "b", "bb", "bbb", ... "c"
#
# Each line defines a matcher that can be referenced within the definition of another matcher using the {_reference_} token. Each definition is broken into options separated by '|'. Only one option is matched per definition. '*', '+' and '?' work as they do in Regex. If a '*' or '+' is followed by "(/_regex_/)" then the contained Regex is treated as a delimiter for any repetition. Regex statements can be interspersed in the definition, but it is not captured as data unless it is the only element (ie. the 'option_a' or 'option_b_regex' definitions in the example).
#
# I welcome optimizations and better debug output, but I don't want to change its method for parsing via definitions.


class DefinitionParser
  attr_reader :definition

  def initialize(definition_string)
    @definition = {}
    definition_string.each_line do |line|
      unless line.strip.size == 0
        name_value = line.match(/(\w+)=(.+)/)
        @definition[name_value[1]] = match_definition(name_value[2])
      end
    end
  end
  
  def match_definition(string)
    log("#{__LINE__}. #{string}")
    data = []
    
    if mdata_string = match_definition_component(string)
      mdata,string = mdata_string
      data << mdata
    end
    
    log("#{__LINE__}. #{string}")
    while (match = string.match(/\A\|/)) and mdata_string = match_definition_component(match.post_match)
      mdata,string = mdata_string
      log("#{__LINE__}. #{string}")
      data << mdata
    end
    
    if string.size == 0
      data
    else
      nil
    end
  end
  
  def match_definition_component(string)
    log("#{__LINE__}. #{string}")
    data = {:type => :component, :elements => []}
    
    while mdata_string = match_element(string)
      mdata,string = mdata_string
      data[:elements] << mdata
    end
    
    [data,string]
  end
  
  def match_element(string)
    data = {}
    log("#{__LINE__}. #{string}")
    if match = string.match(/\A\{(\w+)\}/)
      data[:type] = :reference
      data[:name] = match[1]
      string = match.post_match
    elsif match = string.match(/\A\/((\\\/|[^\/])*)\//)
      data[:type] = :regex
      data[:value] = match[1]
      string = match.post_match
    else
      return nil
    end
    log("#{__LINE__}. #{string}")
    
    if match = string.match(/\A[*+]/)
      data[:type] = match[0]
      string = match.post_match
      
      # find a delimiter for repetition
      if match = string.match(/\A\(\/((\\\/|[^\/])*)\/\)/)
        data[:delimiter] = match[1]
        string = match.post_match
      end
    elsif match = string.match(/\A\?/)
      data[:type] = match[0]
      string = match.post_match
    end
    
    [data,string]
  end

  def log(str)
    #p caller[0].split('`').last[0..-2] + "()----------------------"
    #p str
  end
end


class RuleMatch
  attr_accessor :name
  attr_accessor :value
  
  def pretty_print(q)
    q.text "{#{name}:"
    q.breakable
    q.pp value
    q.breakable
    q.text '}'
  end
end


class Parser
  
  def initialize(definition)
    pp definition
    @definition = definition
  end
  
  def parse(string)
    data,string = match_reference('start',string)
    data
  end
  
  def match_reference(name,string)
    log("#{__LINE__}",'::reference: '+name,string)
    #print name
    data = RuleMatch.new
    data.name = name
    @definition[name].each do |component|
      if mdata_string = match_component(component,string)
        data.value,string = mdata_string
        log("#{__LINE__}",'::matched: '+data.value.inspect,string)
        return [data,string]
      end
    end
    return nil
  end
  
  def match_component(component,string)
    log("#{__LINE__}",component,string)
    #p component
    # a single regex is a capture
    if component[:elements].size == 1 and component[:elements].first[:type] == :regex
      log("#{__LINE__}",component[:elements].first,string)
      if match = string.match(Regexp.new("\\A"+component[:elements].first[:value]))
        string = match.post_match
        log("#{__LINE__}",match[0],string)
        return [match[0],string]
      else
        return nil
      end
    else # return references only
      log("#{__LINE__}",component,string)
      data = []
      component[:elements].each do |element|
        case element[:type]
        when :reference
          log("#{__LINE__}",element,string)
          if mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data << mdata
          else
            return nil
          end
        when :regex
          log("#{__LINE__}",element,string)
          if match = string.match(Regexp.new("\\A"+element[:value]))
            # no capture
            string = match.post_match
          else
            return nil
          end
        when '*'
          while mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data << mdata
            
            # find delimiter
            if element[:delimiter]
              if match = string.match(Regexp.new("\\A"+element[:delimiter]))
                string = match.post_match
              else
                break
              end
            end
          end
        when '?'
          log("#{__LINE__}",element,string)
          if mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data << mdata
          else
            # this is optional, so keep going
          end
        when '+'
          log("#{__LINE__}",element,string)
          data = []
          if mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data << mdata
            
            # find delimiter
            if element[:delimiter]
              if match = string.match(Regexp.new("\\A"+element[:delimiter]))
                string = match.post_match
              else
                return [data,string]
              end
            end
          else
            return nil
          end
          
          while mdata_string = match_reference(element[:name],string)
            log("#{__LINE__}",element,string)
            mdata,string = mdata_string
            data << mdata
            
            # find delimiter
            if element[:delimiter]
              if match = string.match(Regexp.new("\\A"+element[:delimiter]))
                string = match.post_match
              else
                break
              end
            end
          end
        else
          return nil
        end
      end
      if data.size == 1
        data = data.first
      end
      [data,string]
    end
  end
  
  def log(line,element,string)
    p caller[0].split('`').last[0..-2] + "()--------- " + element.inspect
    p line + '. ' + string
  end
end

file = File.new("../examples/main.co")

require 'pp'

definition_parser = DefinitionParser.new(<<-DEFINITION
start={comment}*{context}+/\\s*/
context={name}/\\(/{context_argument}*(/, /)/\\)/{definition}
context_argument={variable}/ = /{context_argument_value}
context_argument_value={symbol}|{operation}

definition=/ = \\{\\s*/{statement}*(/\\s*/)/\\s*/{context}*(/\\s*/)/\\s*\\}/
statement={return_value}|{variable_assignment}|{value}
variable_assignment={variable}/ = /{value}
value=/\\(/{statement}/\\)/|{control_statement}|{object}{operation}*

control_statement={if_control_statement}|{while_control_statement}
if_control_statement=/if +/{condition}{statement}{elsif_control_statement}*{else_control_statement}?/end\b/
elsif_control_statement=/elsif +/{condition}{statement}/end\b/
else_control_statement=/else\b/{statement}/end\b/
while_control_statement=/while +/{condition}{statement}/end\b/
condition=/\\(/{statement}/\\)/|{object}{operation}*


operation=/[ \\t]*/{operator}/[ \\t]*/{value}
operator=/[*\\/]|==|!=|>|<|>=|<=|and\\b|or\\b/

object={nil}|{object_path}|{operation}
object_path={constant}|{variable}{method_path}*|{method}{method_path}*

method={name}/\\(/{method_argument}*(/, /)/\\[ \t]*(?!=)/
method_argument={symbol}/ = /{operation}
method_path=/\\./{method}|/\\./{variable}

return_value=/return +/{statement}

symbol=/:\\w+/
variable={name}/(?!\\()/
string=/"/{string_text}/"/
string_text=/(\\"|[^"])*/
constant={float}|{integer}|{character}|{pointer}
character=/'/{char}/'/
char=/'|[^']/
integer=/\\d+/
float=/\\d+\\.\\d+/
pointer={nil}|{pointer_hex}
pointer_hex=/0x[A-F0-9]+/
name=/\\w+/
nil=/\\bnil\\b/

comment=/\\s*#/{comment_text}/\\n|$/
comment_text=/.*/
DEFINITION
)


parser = Parser.new(definition_parser.definition)
p "========================"
pp parser.parse(file.read)

