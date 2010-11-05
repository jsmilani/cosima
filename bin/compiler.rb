
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


class Parser
  
  def initialize(definition)
    @definition = definition
  end
  
  def parse(string)
    data,string = match_reference('start',string)
    data
  end
  
  def match_reference(name,string)
    log("#{__LINE__}",'::reference: '+name,string)
    #print name
    @definition[name].each do |component|
      if mdata_string = match_component(component,string)
        mdata,string = mdata_string
        log("#{__LINE__}",'::matched: '+mdata.inspect,string)
        return [mdata,string]
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
      data = {}
      component[:elements].each do |element|
        case element[:type]
        when :reference
          log("#{__LINE__}",element,string)
          if mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data[element[:name]] = mdata
          else
            return nil
          end
        when :regex
          log("#{__LINE__}",element,string)
          if match = string.match(Regexp.new("\\A"+element[:value]))
            string = match.post_match
          else
            return nil
          end
        when '*'
          log("#{__LINE__}",element,string)
          data[element[:name]] = []
          while mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data[element[:name]] << mdata
            
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
            data[element[:name]],string = mdata_string
          else
            data[element[:name]] = nil
          end
        when '+'
          log("#{__LINE__}",element,string)
          data[element[:name]] = []
          if mdata_string = match_reference(element[:name],string)
            mdata,string = mdata_string
            data[element[:name]] << mdata
            
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
            data[element[:name]] << mdata
            
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
      [data,string]
    end
  end
  
  def log(line,element,string)
    #p caller[0].split('`').last[0..-2] + "()--------- " + element.inspect
    #p line + '. ' + string
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
statement={variable_assignment}|{value}
variable_assignment={variable}/ = /{value}
value=/\\(/{statement}/\\)/|{object}{operation}*
operation=/\\s*/{operator}/\\s*/{value}
operator=/[*\\/]|==|!=|>|<|>=|<=|and\\b|or\\b/

object={nil}|{object_path}|{operation}
object_path={constant}|{variable}{method_path}*|{method}{method_path}*

method={name}/\\(/{method_argument}*(/, /)/\\[ \t]*(?!=)/
method_argument={symbol}/ = /{operation}
method_path=/\\./{method}|/\\./{variable}


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
#pp definition_parser.definition
#p '----------------'
parser = Parser.new(definition_parser.definition)

pp parser.parse(file.read)

# pp parser.parse(<<-MAIN
# main(args = :Array) = {
#   var = 1
#   
#   print() = {
#     var2 = 1.0
#   }
# }
# MAIN
# )
