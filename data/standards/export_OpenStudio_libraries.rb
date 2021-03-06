# This file contains methods that export some of the contents of the
# OpenStudio-Standards to library .osm files that are packaged
# with the OpenStudio installer.
# These library .osm files are not used by the OpenStudio-Standards gem,
# but this export functionality is part of the gem because the
# gem itself contains the content needed for the libraries.

require 'json'
require 'openstudio'
require_relative '../../lib/openstudio-standards'

def export_openstudio_libraries

  ### Define what to include in the libraries ###
  include_construction_sets = true # Construction Sets, Constructions, and Materials
  include_space_types = true # Space Types, Internal Loads, and associated Schedule Sets and Schedules
  include_boilers = true # BoilerHotWater
  include_chillers = true # ChillerElectricEIR
  include_unitary_acs = true # CoilCoolingDXSingleSpeed
  include_heat_pumps = true # CoilCoolingDXSingleSpeed, CoilHeatingDXSingleSpeed, AirLoopHVACUnitaryHeatPump

  # Make an initial Standard to access the library data
  std = Standard.build('90.1-2013')

  # Read in the map of valid template/climate zone combinations
  temp = File.read("#{__dir__}/templates_to_climate_zones.json")
  templates_to_climate_zones = JSON.parse(temp)

  # Make a library model for each template
  template_to_lib_models = {}
  std.standards_data["templates"].each do |template|
    template_name = template['name']
    data = {}
    data['model'] = OpenStudio::Model::Model.new
    begin
      data['standard_applier'] = Standard.build(template_name)
      template_to_lib_models[template_name] = data
    rescue Exception => e
      puts "'#{template_name}' is not defined in OpenStudio-Standards yet"
    end
  end

  # Construction Sets, Constructions, and Materials
  # TODO fix code to remove duplicate constructions and materials
  if include_construction_sets
    std.standards_data['construction_sets'].each do |props|
      lib = template_to_lib_models[props['template']]
      next if lib.nil? # Skip unsupported templates
      model = lib['model']
      std_applier = lib['standard_applier']

      # Add a construction set for each valid climate zone
      templates_to_climate_zones[props['template']].each do |climate_zone|
        construction_set = std_applier.model_add_construction_set(model,
                                                                  climate_zone,
                                                                  props['building_type'],
                                                                  props['space_type'],
                                                                  props['is_residential'])
      end
    end
  end

  # Space Types
  if include_space_types
    std.standards_data['space_types'].each do |props|
      lib = template_to_lib_models[props['template']]
      next if lib.nil? # Skip unsupported templates
      model = lib['model']
      std_applier = lib['standard_applier']

      # Create a new space type
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsBuildingType(props['building_type'])
      space_type.setStandardsSpaceType(props['space_type'])
      space_type.setName("#{props['building_type']} #{props['space_type']}")

      # Rendering color
      std_applier.space_type_apply_rendering_color(space_type)

      # Loads
      std_applier.space_type_apply_internal_loads(space_type, true, true, true, true, true, true)

      # Schedules
      std_applier.space_type_apply_internal_load_schedules(space_type, true, true, true, true, true, true, true)

    end
  end

  # Boilers
  if include_boilers
    std.standards_data['boilers'].each do |props|
      lib = template_to_lib_models[props['template']]
      next if lib.nil? # Skip unsupported templates
      # Skip NECB 2011 for now
      next if props['template'] == 'NECB 2011'
      model = lib['model']
      std_applier = lib['standard_applier']

      # Make a new boiler
      boiler = OpenStudio::Model::BoilerHotWater.new(model)
      # Fuel Type
      case props['fuel_type']
      when 'Gas'
        boiler.setFuelType('NaturalGas')
      when 'Electric'
        boiler.setFuelType('Electricity')
      when 'Oil'
        boiler.setFuelType('FuelOil#2')
      end
      # Set capacity to middle of range
      min_cap_btu_per_hr = props['minimum_capacity'].to_f
      max_cap_btu_per_hr = props['maximum_capacity'].to_f
      mid_cap_btu_per_hr = (min_cap_btu_per_hr + max_cap_btu_per_hr) / 2
      mid_cap_w = OpenStudio.convert(mid_cap_btu_per_hr, 'Btu/hr', 'W').get
      boiler.setNominalCapacity(mid_cap_w)

      # Apply the standard
      std_applier.boiler_hot_water_apply_efficiency_and_curves(boiler)

      # Reset the capacity
      boiler.autosizeNominalCapacity

      # Modify the name of the boiler to reflect the capacity range
      min_cap_kbtu_per_hr = OpenStudio.convert(min_cap_btu_per_hr, 'Btu/hr', 'kBtu/hr').get.round
      max_cap_kbtu_per_hr = OpenStudio.convert(max_cap_btu_per_hr, 'Btu/hr', 'kBtu/hr').get.round

      old_name = boiler.name.get.to_s
      m = old_name.match(/(\d+)kBtu\/hr/)
      if m
        # Put the fuel type into the name
        old_type = 'Boiler Hot Water 1'
        new_type = "#{props['fuel_type']} Boiler"
        new_name = old_name.gsub(old_type, new_type)
        # Swap out the capacity number for a range
        old_cap = m[1]
        if max_cap_kbtu_per_hr == 10_000_000 # Value representing infinity
          new_cap = "> #{min_cap_kbtu_per_hr}"
        else
          new_cap = "#{min_cap_kbtu_per_hr}-#{max_cap_kbtu_per_hr}"
        end
        new_name = new_name.gsub(old_cap, new_cap)
        boiler.setName(new_name)
        puts "#{props['template']}: #{boiler.name.get.to_s}"
      end

    end
  end

  # Chillers
  if include_chillers
    std.standards_data['chillers'].each do |props|
      lib = template_to_lib_models[props['template']]
      next if lib.nil? # Skip unsupported templates
      # Skip NECB 2011 for now
      next if props['template'] == 'NECB 2011'
      model = lib['model']
      std_applier = lib['standard_applier']

      # Skip absorption chillers
      next unless props['absorption_type'].nil?

      # Skip interim chiller efficiency requirements
      next unless props['end_date'] == "2999-09-09T00:00:00+00:00"

      # Make a new chiller
      chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
      # Set capacity to middle of range
      min_cap_tons = props['minimum_capacity'].to_f
      max_cap_tons = props['maximum_capacity'].to_f
      mid_cap_tons = (min_cap_tons + max_cap_tons) / 2
      mid_cap_w = OpenStudio.convert(mid_cap_tons, 'ton', 'W').get
      chiller.setReferenceCapacity(mid_cap_w)

      # Add the chiller properties to the name, because this is what
      # the standards currently work off of.
      if props['cooling_type'] == 'AirCooled'
        new_name = "#{props['cooling_type']} Chiller #{props['condenser_type']}"
      elsif props['cooling_type'] == 'WaterCooled'
        new_name = "#{props['cooling_type']} #{props['compressor_type']} Chiller"
      else
        new_name = chiller.name.get
      end
      chiller.setName(new_name)

      # Apply the standard
      std_applier.chiller_electric_eir_apply_efficiency_and_curves(chiller, nil)

      # Reset the capacity
      chiller.autosizeReferenceCapacity

      # Modify the name of the chiller to reflect the capacity range
      old_name = chiller.name.get.to_s
      m = old_name.match(/(\d+)tons/)
      if m
        # Put the fuel type into the name
        old_type = 'Chiller Electric EIR 1'
        new_type = 'Chiller'
        new_name = old_name.gsub(old_type, new_type)
        # Swap out the capacity number for a range
        old_cap = m[1]
        if max_cap_tons == 10_000 # Value representing infinity
          new_cap = "> #{min_cap_tons.round}"
        else
          new_cap = "#{min_cap_tons.round}-#{max_cap_tons.round}"
        end
        new_name = new_name.gsub(old_cap, new_cap)
        chiller.setName(new_name)
        puts "#{props['template']}: #{chiller.name.get.to_s}"
      end

    end
  end

  # Unitary AC
  if include_unitary_acs
    std.standards_data['unitary_acs'].each do |props|
      lib = template_to_lib_models[props['template']]
      next if lib.nil? # Skip unsupported templates
      # Skip NECB 2011 for now
      next if props['template'] == 'NECB 2011'
      model = lib['model']
      std_applier = lib['standard_applier']

      # Skip interim efficiency requirements
      next unless props['end_date'] == "2999-09-09T00:00:00+00:00"

      # Make a new DX coil
      dx_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
      # Set capacity to middle of range
      min_cap_btu_per_hr = props['minimum_capacity'].to_f
      max_cap_btu_per_hr = props['maximum_capacity'].to_f
      mid_cap_btu_per_hr = (min_cap_btu_per_hr + max_cap_btu_per_hr) / 2
      mid_cap_w = OpenStudio.convert(mid_cap_btu_per_hr, 'Btu/hr', 'W').get
      dx_coil.setRatedTotalCoolingCapacity(mid_cap_w)

      # Add the subcategory to the name so that it
      # can be used by the efficiency lookup
      dx_coil.setName("#{dx_coil.name} #{props['subcategory']}")

      # If it is a PTAC coil, add to PTAC
      if props['subcategory'] == 'PTAC'
        htg_coil = nil
        if props['heating_type'] == 'Electric Resistance or None'
          htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
          htg_coil.setName('PTAC Electric Backup Htg Coil')
        else
          htg_coil = OpenStudio::Model::CoilHeatingGas.new(model)
          htg_coil.setName('PTAC Gas Backup Htg Coil')
        end
        fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)
        fan.setName("PTAC Supply Fan")
        ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                             model.alwaysOnDiscreteSchedule,
                                                                             fan,
                                                                             htg_coil,
                                                                             dx_coil)
      end

      # Apply the standard
      std_applier.coil_cooling_dx_single_speed_apply_efficiency_and_curves(dx_coil, {})

      # Reset the capacity
      dx_coil.autosizeRatedTotalCoolingCapacity

      # Modify the name of the boiler to reflect the capacity range
      min_cap_kbtu_per_hr = OpenStudio.convert(min_cap_btu_per_hr, 'Btu/hr', 'kBtu/hr').get.round
      max_cap_kbtu_per_hr = OpenStudio.convert(max_cap_btu_per_hr, 'Btu/hr', 'kBtu/hr').get.round

      # Modify the name of the dx_coil to reflect the capacity range
      old_name = dx_coil.name.get.to_s
      m = old_name.match(/(\d+)kBtu\/hr/)
      if m
        # Put the fuel type into the name
        old_type = "Coil Cooling DX Single Speed 1 #{props['subcategory']}"
        new_type = "#{props['cooling_type']} #{props['heating_type']} #{props['subcategory']} DX"
        new_name = old_name.gsub(old_type, new_type)
        # Swap out the capacity number for a range
        old_cap = m[1]
        if max_cap_kbtu_per_hr ==  10_000 # Value representing infinity
          new_cap = "> #{min_cap_kbtu_per_hr}"
        else
          new_cap = "#{min_cap_kbtu_per_hr}-#{max_cap_kbtu_per_hr}"
        end
        new_name = new_name.gsub(old_cap, new_cap)
        dx_coil.setName(new_name)
        puts "#{props['template']}: #{dx_coil.name.get.to_s}"

        # Rename PTAC too
        if props['subcategory'] == 'PTAC'
          ptac.setName("PTAC #{new_name}")
        end

      end

    end
  end

  # Heat Pumps
  if include_heat_pumps
    std.standards_data['heat_pumps'].each do |props|
      lib = template_to_lib_models[props['template']]
      next if lib.nil? # Skip unsupported templates
      # Skip NECB 2011 for now
      next if props['template'] == 'NECB 2011'
      model = lib['model']
      std_applier = lib['standard_applier']

      # Skip interim efficiency requirements
      next unless props['end_date'] == "2999-09-09T00:00:00+00:00"

      # Make a new DX cooling coil
      clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
      # Set capacity to middle of range
      min_clg_cap_btu_per_hr = props['minimum_capacity'].to_f
      max_clg_cap_btu_per_hr = props['maximum_capacity'].to_f
      mid_clg_cap_btu_per_hr = (min_clg_cap_btu_per_hr + max_clg_cap_btu_per_hr) / 2
      mid_clg_cap_w = OpenStudio.convert(mid_clg_cap_btu_per_hr, 'Btu/hr', 'W').get
      clg_coil.setRatedTotalCoolingCapacity(mid_clg_cap_w)

      # Make a new DX heating coil sized at 90% of the capacity
      # of the cooling coil.
      htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
      mid_htg_cap_w = mid_clg_cap_w * 0.9
      htg_coil.setRatedTotalHeatingCapacity(mid_htg_cap_w)

      # If it is a PTHP Coil, add to PTHP
      # If not, add to unitary HP
      if props['subcategory'] == 'PTHP'
        if props['heating_type'] == 'Electric Resistance or None'
          backup_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
          backup_htg_coil.setName('PTHP Electric Backup Htg Coil')
        else
          backup_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model)
          backup_htg_coil.setName('PTHP Electric Backup Htg Coil')
        end
        fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)
        fan.setName("PTHP Supply Fan")
        pthp = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(model,
                                                                       model.alwaysOnDiscreteSchedule,
                                                                       fan,
                                                                       htg_coil,
                                                                       clg_coil,
                                                                       backup_htg_coil)
      else
        if props['heating_type'] == 'Electric Resistance or None'
          backup_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
          backup_htg_coil.setName('Unitary Heat Pump Electric Backup Htg Coil')
        else
          backup_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model)
          backup_htg_coil.setName('Unitary Heat Pump Electric Backup Htg Coil')
        end
        fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)
        fan.setName("Unitary Heat Pump Supply Fan")
        unitary_system = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(model,
                                                                                   model.alwaysOnDiscreteSchedule,
                                                                                   fan,
                                                                                   htg_coil,
                                                                                   clg_coil,
                                                                                   backup_htg_coil)
        unitary_system.setName("Unitary Heat Pump")
        unitary_system.setMaximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation(OpenStudio.convert(40, 'F', 'C').get)
      end

      # Apply the standard
      std_applier.coil_cooling_dx_single_speed_apply_efficiency_and_curves(clg_coil, {})
      std_applier.coil_heating_dx_single_speed_apply_efficiency_and_curves(htg_coil, {})

      # Reset the capacity
      clg_coil.autosizeRatedTotalCoolingCapacity
      htg_coil.autosizeRatedTotalHeatingCapacity

      # Modify the name of the boiler to reflect the capacity range
      min_clg_cap_kbtu_per_hr = OpenStudio.convert(min_clg_cap_btu_per_hr, 'Btu/hr', 'kBtu/hr').get.round
      max_clg_cap_kbtu_per_hr = OpenStudio.convert(max_clg_cap_btu_per_hr, 'Btu/hr', 'kBtu/hr').get.round

      # Modify the name of the dx_coil to reflect the capacity range
      old_name = clg_coil.name.get.to_s
      m = old_name.match(/(\d+)kBtu\/hr/)
      if m
        # Put the fuel type into the name
        old_type = 'Coil Cooling DX Single Speed 1'
        new_type = "#{props['cooling_type']} #{props['heating_type']} #{props['subcategory']} DX"
        new_name = old_name.gsub(old_type, new_type)
        # Swap out the capacity number for a range
        old_cap = m[1]
        if max_clg_cap_kbtu_per_hr ==  10_000 # Value representing infinity
          new_cap = "> #{min_clg_cap_kbtu_per_hr}"
        else
          new_cap = "#{min_clg_cap_kbtu_per_hr}-#{max_clg_cap_kbtu_per_hr}"
        end
        new_name = new_name.gsub(old_cap, new_cap)
        clg_coil.setName(new_name)
        puts "#{props['template']}: #{clg_coil.name.get.to_s}"

        # Rename PTHP or unitary same as the cooling coil
        if pthp
          pthp.setName("PTHP #{new_name}")
        else
          unitary_system.setName("Unitary Heat Pump #{new_name}")
        end

        # Rename the heating coil
        old_type = 'Coil Heating DX Single Speed 1'
        new_type = "#{props['cooling_type']} #{props['heating_type']} #{props['subcategory']} DX"
        new_name = old_name.gsub(old_type, new_type)
        # Swap out the capacity number for a blank
        old_cap = m[1]
        new_name = new_name.gsub(old_cap, '')
        htg_coil.setName(new_name)

      end

    end
  end

  # Delete all the unused curves
  puts 'Cleaning up the unused curves'
  template_to_lib_models.each do |template, data|
    puts ''
    puts "***#{template}***"
    data['model'].getCurves.sort.each do |curve|
      if curve.directUseCount == 0
        puts "    #{curve.name} is unused; successfully removed? #{data['model'].removeObject(curve.handle)}."
        # curve.remove # For some reason curve.remove doesn't work properly
      end
    end
  end

  # Save the libraries
  osm_lib_dir = "#{__dir__}/../../pkg/libraries"
  Dir.mkdir(osm_lib_dir) unless Dir.exists?(osm_lib_dir)
  template_to_lib_models.each do |template, data|
    library_path = "#{osm_lib_dir}/#{template.gsub(/\W/,'_')}.osm"
    puts "Saving library #{library_path}"
    data['model'].save(OpenStudio::Path.new(library_path), true)
  end

end
