#
# Copyright 2010 Opscode, Inc. 
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'tempfile'

# A wrapper around cfityk (http://fityk.nieto.pl/) to handle fitting a curve to X+Y data, creating confidence intervals, and projecting up to a ceiling.
#
# Also supports basic manipulation of X+Y data files.
class CurveFit

  attr_accessor :debug

  def initialize(debug=false)
    @debug = debug
  end

  # Loads an x+y style data file as an array of arrays, suitable for passing to the fit method.
  #
  # @param [String] filename 
  #   The filename to load.
  # @return [Array] data
  #   An X+Y array: 
  #     [ [ X, Y ], [ X, Y ] ]
  def load_xy_file(filename)
    xy_data = Array.new
    File.open(filename, "r") do |xy_file|
      xy_file.each_line do |line|
        x, y = line.split(' ')
        xy_data << [ string_to_number(x), string_to_number(y) ] 
      end
    end
    xy_data
  end

  # Takes a string of digits and converts it to an integer or a float,
  # depending on whether it rocks the dot. Returns the raw string if nothing
  # matches.
  #
  # @param [String] string
  # @return [Integer,Float,String] transformed_string
  def string_to_number(string)
    case string
    when /^\d+$/
      string.to_i
    when /^\d+.\d$/
      string.to_f
    else 
      string
    end
  end

  # Adds an entry to an x+y style data file.
  #
  # @param [String] filename 
  #   The filename to append to
  # @param [String] x 
  #   The X value
  # @param [String] y 
  #   The Y value
  # @return [True]
  def append_xy_file(filename, x, y)
    File.open(filename, 'a') do |xy_file|
      xy_file.puts "#{x} #{y}" 
    end
    true
  end

  # Writes a data set out to an X+Y file
  #
  # @param [Array] data
  #   An X+Y array: 
  #     [ [ X, Y ], [ X, Y ] ]
  # @param [String] filename
  #   If given, the filename to write. Otherwise, creates a tempfile.
  # @return [IO] data_file Returns the closed file IO object.
  def write_xy_file(data, filename=nil)
    data_file = nil
    if filename
      data_file = File.open(filename, "w")
    else
      data_file = Tempfile.new("curvefit") 
      filename = data_file.path
    end

    data.each do |point|
      data_file.puts("#{point[0]} #{point[1]}")
    end

    data_file.close
    
    data_file
  end

  # Given an aray of X,Y data points, guesses the most correct curve (as measured by R-Squared) and
  # generates a trend line, top and bottom confidence intervals, and optionally projects the trend
  # to an artifical ceiling.
  #
  # @param [Array] data
  #   An array of arrays [[X, Y]..] representing the data set you want to curve fit.
  #
  # @param [Number, nil] ceiling 
  #   The integer/float Y value to project the curve up to, the 'ceiling'. Nil
  #   means no projection past last X value.  Default is nil.
  #
  # @param [Array] guess_list 
  #   A list of acceptable guesses to use in cfityk. As many of
  #   the following as desired: Linear, Quadratic. Default is all of the above.
  #
  # @param [Block] x_transform  
  #   A block that will be passed a value for X from the original
  #   data set as an integer (1,2,3, etc), and should return a value to replace
  #   it with that matches the original data set. 
  #
  # @return [Hash] A hash with the data, trend, top_confidence, and bottom_confidence as arrays of [X, Y], r_square and the guessed curve.
  #
  #  {
  #    :data => [ [ X, Y ], [ X, Y ] ... ],
  #    :trend => [ [ X, Y ], [ X, Y ] ... ],
  #    :top_confidence => [ [ X, Y ],  [X, Y] ...],
  #    :bottom_confidence => [ [ X, Y ], [X, Y] ...],
  #    :ceiling => [ [ X, Y ], [ X, Y ] ],
  #    :r_squared => 99.9764,
  #    :guess => "Quadratic" 
  #  }
  #
  def fit(data, ceiling=nil, guess_list=["Linear", "Quadratic"], &x_transform)
    data_file = Tempfile.new("curvefit") 
    x_pos = 0
    data.each do |point|
      data_file.puts("#{x_pos} #{point[1]}")
      x_pos += 1
    end
    data_file.close

    guess_data = Hash.new
 
    guess_list.each do |shape|
      guess_data[shape] = Hash.new
      puts "Guessing #{shape} fit..." if @debug
      IO.popen("cfityk -I -q -c '@0 < '#{data_file.path}'; guess #{shape}; fit; info+ formula in @0; info fit in @0; info errors in @0;'") do |fityk_output|
        fityk_output.each_line do |line|
          puts "#{shape}: #{line}" if @debug
          case line
          when /R-squared = (.+)/
            guess_data[shape][:r_squared] = $1.to_f
          when /(.+) \+ (.+) \* \(x\)/ # 692.1 + 30.633 * (x), linear fit formula
            first = $1.to_f
            second = $2.to_f
            guess_data[shape][:curve_formula] = lambda { |x| first + second * x.to_f }
          when /(.+) \+ (.+)\*\(x\) \+ (.+)\*\(x\)\^2/ # 1019.43 + 9.543*(x) + 0.202086*(x)^2, quadratic/polynomial fit formula
            first = $1.to_f
            second = $2.to_f
            third = $3.to_f
            guess_data[shape][:curve_forumla_args] = {
              1 => first,
              2 => second,
              3 => third
            }
            guess_data[shape][:curve_formula] = lambda { |x| first + second * x.to_f + third * x.to_f**2 }
          when /\$_(\d) = (\d+\.\d+) \+\- (\d+\.\d+)/ # $_1 = 692.1 +- 32.0558
            guess_data[shape][:curve_error_args] ||= Hash.new 
            guess_data[shape][:curve_error_args][$1.to_i] = [ $2.to_f, $3.to_f ]
          end
        end
      end

      if $?.exitstatus != 0
        raise "cfityk returned status #{$?.exitstatus} when guessing #{shape}, bailing"
      end
     
      if guess_data[shape][:r_squared] == 1
        guess_data[shape][:top_confidence_formula] = guess_data[shape][:curve_formula] 
        guess_data[shape][:bottom_confidence_formula] = guess_data[shape][:curve_formula]
      else
        case shape
        when "Quadratic"
          curve_error_args = guess_data[shape][:curve_error_args]
          guess_data[shape][:top_confidence_formula] = lambda { |x| (curve_error_args[1][0] + curve_error_args[1][1]) + (curve_error_args[2][0] + curve_error_args[2][1]) * x.to_f + (curve_error_args[3][0] + + curve_error_args[3][1]) * x.to_f**2 }
          guess_data[shape][:bottom_confidence_formula] = lambda { |x| (curve_error_args[1][0] - curve_error_args[1][1]) + (curve_error_args[2][0] - curve_error_args[2][1]) * x.to_f + (curve_error_args[3][0] + - curve_error_args[3][1]) * x.to_f**2 }
        when "Linear"
          curve_error_args = guess_data[shape][:curve_error_args]
          guess_data[shape][:top_confidence_formula] = lambda { |x| (curve_error_args[1][0] + curve_error_args[1][1]) + (curve_error_args[2][0] + curve_error_args[2][1]) * x.to_f } 
          guess_data[shape][:bottom_confidence_formula] = lambda { |x| (curve_error_args[1][0] - curve_error_args[1][1]) + (curve_error_args[2][0] - curve_error_args[2][1]) * x.to_f }
        end
      end
    end

    best_fit_name = nil
    best_fit = nil
    guess_data.each do |shape, shape_guess|
      best_fit_name ||= shape
      best_fit ||= shape_guess
      if shape_guess[:r_squared] > best_fit[:r_squared]
        best_fit = shape_guess 
        best_fit_name = shape
      end
    end

    trend_line = []
    top_confidence_line = []
    bottom_confidence_line = []
    ceiling_line = []

    x = 0 
    y = 0

    no_ceiling = ceiling.nil?

    while(no_ceiling ? x < data.length : ceiling >= y) 
      y = best_fit[:curve_formula].call(x)
      y_top_confidence = best_fit[:top_confidence_formula].call(x)
      y_bottom_confidence = best_fit[:bottom_confidence_formula].call(x)

      if x_transform
        trend_line << [ x_transform.call(x), y ]
        top_confidence_line << [ x_transform.call(x), y_top_confidence ]
        bottom_confidence_line << [ x_transform.call(x), y_bottom_confidence ]
        ceiling_line << [ x_transform.call(x), ceiling ] unless no_ceiling
      else
        trend_line << [ x, y ]
        top_confidence_line << [ x, y_top_confidence ]
        bottom_confidence_line << [ x, y_bottom_confidence ]
        ceiling_line << [ x, ceiling ] unless no_ceiling
      end

      x += 1
    end

    {
      :data => data,
      :trend => trend_line,
      :top_confidence => top_confidence_line,
      :bottom_confidence => bottom_confidence_line,
      :ceiling => ceiling_line,
      :r_squared => best_fit[:r_squared],
      :guess => best_fit_name 
    }
  end
   
end
