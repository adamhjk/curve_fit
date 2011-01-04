require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'tempfile'

describe "CurveFit" do
  PERFECTLY_LINEAR_DATA = [
    [ 0, 1000.0 ],
    [ 1, 2000.0 ],
    [ 2, 3000.0 ],
    [ 3, 4000.0 ],
    [ 4, 5000.0 ],
    [ 5, 6000.0 ]
  ] 

  LINEAR_DATA = [
    [ 0, 1000.0 ],
    [ 1, 2003.0 ],
    [ 2, 3010.0 ],
    [ 3, 4084.0 ],
    [ 4, 5012.0 ],
    [ 5, 6075.0 ]
  ] 

  QUADRATIC_DATA = [[0, 1024.0], [1, 1038.0], [2, 1054.0], [3, 1062.0], [4, 1070.0], [5, 1074.0], [6, 1077.0], [7, 1085.0], [8, 1107.0], [9, 1146.0], [10, 1133.0], [11, 1145.0], [12, 1142.0], [13, 1161.0], [14, 1183.0], [15, 1172.0], [16, 1194.0], [17, 1219.0], [18, 1280.0], [19, 1301.0], [20, 1303.0], [21, 1332.0], [22, 1391.0], [23, 1338.0], [24, 1368.0], [25, 1383.0], [26, 1414.0], [27, 1417.0], [28, 1476.0], [29, 1489.0], [30, 1518.0], [31, 1557.0], [32, 1555.0], [33, 1472.0], [34, 1481.0], [35, 1432.0], [36, 1451.0], [37, 1661.0], [38, 1741.0], [39, 1769.0], [40, 1797.0], [41, 1802.0], [42, 1803.0], [43, 1854.0], [44, 1869.0], [45, 1886.0], [46, 1947.0], [47, 2002.0], [48, 1950.0], [49, 2021.0], [50, 2022.0], [51, 2049.0], [52, 2060.0], [53, 2096.0], [54, 2106.0], [55, 2140.0], [56, 2159.0], [57, 2181.0], [58, 2158.0], [59, 2215.0], [60, 2292.0], [61, 2302.0], [62, 2311.0], [63, 2387.0], [64, 2480.0], [65, 2491.0], [66, 2497.0], [67, 2515.0], [68, 2534.0], [69, 2561.0], [70, 2636.0], [71, 2697.0], [72, 2818.0], [73, 2831.0], [74, 2855.0], [75, 2900.0], [76, 2973.0], [77, 2996.0], [78, 3053.0], [79, 3093.0], [80, 3104.0], [81, 3033.0], [82, 3066.0], [83, 3094.0], [84, 3165.0], [85, 3263.0], [86, 3306.0], [87, 3334.0], [88, 3457.0], [89, 3501.0], [90, 3588.0], [91, 3739.0], [92, 3778.0], [93, 3829.0], [94, 3829.0], [95, 3812.0], [96, 3846.0], [97, 3933.0], [98, 3989.0], [99, 4030.0], [100, 4041.0], [101, 4054.0], [102, 4069.0], [103, 4101.0], [104, 4130.0], [105, 4292.0], [106, 4361.0], [107, 4373.0], [108, 4405.0], [109, 4433.0], [110, 4487.0], [111, 4524.0], [112, 4605.0], [113, 4645.0], [114, 4645.0], [115, 4668.0], [116, 4752.0], [117, 4782.0]]


  before :each do
    @cf = CurveFit.new(false)
  end

  describe "write_xy_file" do
    it "should write to a tempfile" do
      data_file = @cf.write_xy_file(PERFECTLY_LINEAR_DATA, nil)
      File.exists?(data_file.path).should == true
    end

    it "should write to a file" do
      tf = Tempfile.new("curve-fit-funtimes")
      tf.close
      filename = tf.path
      tf.unlink
      data_file = @cf.write_xy_file(PERFECTLY_LINEAR_DATA, filename)
      File.exists?(filename).should == true
      File.unlink(filename)
    end
  end

  describe "load_xy_file" do
    it "should read from an XY file" do
      data_file = @cf.write_xy_file(PERFECTLY_LINEAR_DATA, nil)
      read_data = @cf.load_xy_file(data_file)
      read_data.should == PERFECTLY_LINEAR_DATA
    end
  end

  describe "append_xy_file" do
    it "should add a new value to an XY file" do
      tf = Tempfile.new("curve-fit-funtimes")
      tf.close
      filename = tf.path
      tf.unlink
      data_file = @cf.write_xy_file(PERFECTLY_LINEAR_DATA, filename)
      @cf.append_xy_file(filename, 6, 7000.0)
      appended_data = @cf.load_xy_file(filename)
      appended_data[6].should == [ 6, 7000.0 ]
    end
  end

  describe "fit" do
    describe "for linear data" do
      it "should guess linear" do
        @cf.fit(PERFECTLY_LINEAR_DATA)[:guess].should == "Linear"
      end

    end

    describe "for quadratic data" do
      it "should guess quadratic" do
        @cf.fit(QUADRATIC_DATA)[:guess].should == "Quadratic"
      end
    end

    describe "ceilings" do
      describe "when given" do
        before :each do
          @fit = @cf.fit(PERFECTLY_LINEAR_DATA, 10000)
        end

        it "should be projected to" do
          @fit[:data].length.should == 6
          @fit[:trend].length.should == 11 
          @fit[:top_confidence].length.should == 11 
          @fit[:bottom_confidence].length.should == 11 
        end

        it "should generate a ceiling line as long as the trend line" do
          @fit[:ceiling].length.should == @fit[:trend].length
        end

        it "should always have the y value of the ceiling" do
          @fit[:ceiling].each { |tuple| tuple[1].should == 10000 }
        end
      end

      describe "when nil" do
        it "should have an empty ceiling line" do
          fit = @cf.fit(PERFECTLY_LINEAR_DATA)
          fit[:ceiling].should == []
        end
      end
    end

    describe "when r-squared is 1.0" do
      it "should re-use the fit formula for the trend and confidence intervals" do
        linear_fit = @cf.fit(PERFECTLY_LINEAR_DATA) 
        linear_fit[:data].should == linear_fit[:trend]
        linear_fit[:data].should == linear_fit[:top_confidence]
        linear_fit[:data].should == linear_fit[:bottom_confidence]
      end
    end

    describe "when r-squared is not 1.0" do
      it "should generate different trend and confidence intervals" do
        linear_fit = @cf.fit(LINEAR_DATA) 
        linear_fit[:data].should_not == linear_fit[:trend]
        linear_fit[:data].should_not == linear_fit[:top_confidence]
        linear_fit[:data].should_not == linear_fit[:bottom_confidence]
      end
    end
  end

end
