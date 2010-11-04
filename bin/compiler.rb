# This is a quick and dirty compiler. This compiler will eventually be replaced by a native Cosima compiler, but that needs to be compiled by this one.
# This is a work in progress so don't clean it up yet.

class CosimaParser
  attr_reader :data
  
  def initialize(str)
    @string = str
    @data = match_file(@string)
  end
  
  def match_typecast(string)
    data = {}
    if match = string.match(/\A(\w+)\(/)
      string = match.post_match
      data[:type] = match[0]
      
      if mdata_string = match_statement(string)
        mdata,string = mdata_string
        data[:value] = mdata
        if match = string.match(/\A\s*\)/)
          string = match.post_match
        else
          return nil
        end
      else
        return nil
      end
    else
      return nil
    end
    [data,string]
  end
  
  def match_method_args(string)
    log("#{__LINE__}. #{string}")
    data = {}
    while true
      log("#{__LINE__}. #{string}")
      if match = string.match(/\A\s*:(\w+)\s*=\s*/)
        data[:name] = match[1]
        string = match.post_match
        log("#{__LINE__}. #{string}")
        if match = string.match(/\A:\w+(\.\w+)?/)
          data[:value] = {:type => 'symbol', :name => match[0]}
          string = match.post_match
          log("#{__LINE__}. #{string}")
        elsif mdata_string = match_statement(string,false)
          mdata,string = mdata_string
          data[:value] = mdata
          if match = string.match(/\A\s*,/)
            string = match.post_match
          else
            return [data,string]
          end
        else
          return nil
        end
      else
        return [data,string]
      end
    end
    [data,string]
  end
  
  def match_const(string)
    log("#{__LINE__}. #{string}")
    data = {}
    match = string.match(/\A\s*/)
    string = match.post_match
    
    # 0 or 123123 or 1.002
    # "Some String"
    # [1,2,3] or [1.0,2.0,3.0] I am lazy and only support int and float right now
    
    if match = string.match(/\A"((\\"|[^"])*)"/)
      string = match.post_match
      data[:type] = 'String'
      data[:value] = match[1]
    elsif match = string.match(/\Anil/)
      data[:type] = 'Pointer'
      data[:value] = 0
      string = match.post_match
    elsif match = string.match(/\A\d+/)
      decimal = match[0]
      string = match.post_match
      log("#{__LINE__}. #{string}")
      if match = string.match(/\A\.\d+/)
        data[:type] = 'Float'
        data[:value] = decimal + match[0]
        string = match.post_match
      else
        data[:type] = 'Int'
        data[:value] = decimal
      end
    elsif match = string.match(/\A\[/)
      data[:type] = 'Array'
      data[:values] = []
      string = match.post_match
      while mdata_string = match_const(string)
        mdata,string = mdata_string
        data[:values] << mdata
      end
      
      if match = string.match(/\A\s*\]/)
        string = match.post_match
      else
        return nil
      end
    else
      return nil
    end
    return [data,string]
  end
  
  def match_variable_or_method_or_operator(string)
    log("#{__LINE__}. #{string}")
    data = {}
    
    if mdata_string = match_typecast(string)
      data,string = mdata_string
    elsif mdata_string = match_const(string) # int, array, string, nil
      data,string = mdata_string
    elsif match = string.match(/\A[a-zA-Z]\w*/)
      data[:name] = match[0]
      if %w{if else end while do case when}.include?(data[:name])
        return nil
      end
      string = match.post_match
      log("#{__LINE__}. #{string}")
      if match = string.match(/\A\(/)
        string = match.post_match
        log("#{__LINE__}. #{string}")
        if mdata_string = match_method_args(string)
          mdata,string = mdata_string
          log("#{__LINE__}. #{string}")
          data[:type] = "method"
          data[:arguments] = mdata
          
          if match = string.match(/\A\s*\)/)
            string = match.post_match
            
            # block
            if match = string.match(/\A\s*do\s*(\|(\w+)\|\s*)?/)
              string = match.post_match
              if mdata_string = match_definition(string)
                data[:block],string = match_string
                
                if match = string.match(/\A\w+end/)
                  string = match.post_match
                else
                  return nil
                end
              else
                return nil
              end
            end
          else
            return nil
          end
        else
          return nil
        end
      else # variable
        data[:type] = "variable"
      end
      
    elsif match = string.match(/\A\(\s*/)
      # begin group
      data[:type] = 'group'
      string = match.post_match
      if mdata_string = match_statement(string)
        mdata,string = mdata_string
        data[:value] = mdata
        
        if match = string.match(/\A\s*\)/)
          string = match.post_match
        else
          return nil
        end
      end
    else
      return nil
    end
    
    # check for operator
    if match = string.match(/\A\s*(&&|\|\||[+\-*\/\|&<>]|>=|<=|and|or)\s*/)
      # double check it is an operator so we don't catch ||=, etc.
      if match.post_match.match(/\A[^=]/)
        string = match.post_match
        log("#{__LINE__}. #{string}")
        data = {:type => 'operator', :operator => match[1], :first => data}
      
        if mdata_string = match_statement(string)
          mdata,string = mdata_string
          data[:second] = mdata
        else
          return nil
        end
      end
    end
    
    [data,string]
  end
  
  def match_control_statements(string)
    data = {:type => 'control'}
    if (match = string.match(/\A\s*(\w+)/)) and %w{if while elsif}.include?(match[1])
      data[:control] = match[1]
      string = match.post_match
      if mdata_string = match_match_statement(string,false)
        mdata,string = mdata_string
        data[:condition] = mdata
      else
        return nil
      end
    elsif (match = string.match(/\A\s*(\w+)/)) and match[1] =='end'
      data[:control] = 'end'
    else
      return nil
    end
    
    [data,string]
  end
  
  def match_execution_path(string,control_statements=true)
    log("#{__LINE__}. #{string}")
    data = {}
    
    if control_statements and mdata_string = match_control_statements(string)
      mdata,string = mdata_string
      return [mdata,string]
    elsif mdata_string = match_variable_or_method_or_operator(string)
      mdata,string = mdata_string
      log("#{__LINE__}. #{string}")
      data[:type] = 'execution'
      data[:path] = []
      data[:path] << mdata
      while match = string.match(/\A\./)
        string = match.post_match
        if mdata_string = match_variable_or_method_or_operator(string)
          mdata,string = mdata_string
          data[:path] << mdata
        else
          return nil
        end
      end
    else
      return nil
    end
    
    if data[:path].size == 0
      return nil
    elsif data[:path].size == 1
      return [data[:path].first,string]
    end
    
    [data,string]
  end
  
  # one()
  # one.new()
  # one().two
  # one = two
  # one ||= two
  # one ||= two()
  
  def match_statement(string,allow_assignment=true)
    log("#{__LINE__}. #{string}")
    data = {}
    match = string.match(/\A\s*/)
    string = match.post_match
    
    if mdata_string = match_execution_path(string)
      mdata,string = mdata_string
      log("#{__LINE__}. #{string}")
      data[:subject] = mdata
      
      if allow_assignment and match = string.match(/\A\s*(\|\|=|=|\+=|-=)\s*/)
        string = match.post_match
        data[:type] = "assignment"
        data[:assignment] = match[1]
        if mdata_string = match_execution_path(string)
          mdata,string = mdata_string
          data[:value] = mdata
        else
          return nil
        end
      else
        log("#{__LINE__}. #{string}")
        return [data[:subject],string]
      end
    else
      return nil
    end
    
    [data,string]
  end
  
  def match_yield(string)
    if match = string.match(/\S\s*yield/)
      return [{:type => 'yield'},match.post_match]
    end
    nil
  end
  
  def match_definition(string)
    log("#{__LINE__}. #{string}")
    data = {:statements => [], :contexts => []}
    if match = string.match(/\A\s*/)
      string = match.post_match
      while (dmatch_string = match_statement(string)) || (dmatch_string = match_yield(string))
        dmatch,string = dmatch_string
        data[:statements] << dmatch
      end
      log("#{__LINE__}. #{string}")
      while dmatch_string = match_context(string)
        dmatch,string = dmatch_string
        data[:statements] << dmatch
      end
      log("#{__LINE__}. #{string}")
      return [data,string]
    end
    nil
  end
  
  def match_args(string)
    log("#{__LINE__}. #{string}")
    data = {}
    while match = string.match(/\A\s*(\w+)\s*\=\s*/)
      data[:name] = match[1]
      string = match.post_match
      if match = string.match(/\A:(\w+)/)
        string = match.post_match
        data[:value] = match[1].to_sym
      elsif mdata_string = match_execution_path(string,false)
        mdata,string = mdata_string
        data[:value] = mdata
      else
        return nil
      end
      
      if match = string.match(/\A,/)
        string = match.post_match
      else
        return [data,string]
      end
    end
    [data,string]
  end
  
  def match_context(string)
    log("#{__LINE__}. #{string}")
    
    data = {:type => 'context'}
    if match = string.match(/\A^\s*(\w+)\(/)
      string = match.post_match
      data[:name] = match[1]
      if mdata_string = match_args(match.post_match)
        data[:args],string = mdata_string
        
        if match = string.match(/\A\)\s*(&?=)\s*\{/)
          # assign context
          data[:definition_type] = match[1]
          string = match.post_match
          log("#{__LINE__}. #{string}")
          if mdata_string = match_definition(string)
            data[:definition],string = mdata_string
            log("#{__LINE__}. #{string}")
            if match = string.match(/\A\s*\}\s*/)
              string = match.post_match
            else
              return nil
            end
          end
        elsif match = string.match(/\A\)\s*(@=)\s*/)
          # alias context
          data[:definition_type] = match[1]
          string = match.post_match
          log("#{__LINE__}. #{string}")
          if mdata_string = match_execution_path(string,false)
            mdata,string = mdata_string
            data[:definition] = mdata
          else
            return nil
          end
        else
          return nil
        end
      else
        return nil
      end
    else
      return nil
    end
    [data,string]
  end
  
  def match_file(string)
    data = []
    string.gsub!(/#.*$/,'')
    while mdata_string = match_context(string)
      mdata,string = mdata_string
      data << mdata
    end
    
    if match = string.match(/\A\s*\Z/)
      p "== VALID =="
    else
      p "--------- Leftover -------------"
      p string
      p "--------------------------------"
    end
    data
  end
  
  def log(str)
    p str
  end
end

file = File.new("../examples/main.co")

require 'pp'

parsed = CosimaParser.new(file.read)
pp parsed.data
