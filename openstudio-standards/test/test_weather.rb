require_relative 'minitest_helper'
#class WeatherTests < Minitest::Test
#  # Tests to ensure that the NECB default schedules are being defined correctly.
#  # This is not for compliance, but for archetype development. This will compare
#  # to values in an excel/csv file stored in the weather folder.
#  # NECB 2011 8.4.2.3 
#  # @return [Bool] true if successful. 
#  def test_weather_reading()
#    BTAP::Environment::create_climate_index_file(
#      File.join(File.dirname(__FILE__),'..','data','weather'), 
#      File.join(File.dirname(__FILE__),'weather_test.csv') 
#    )
#    assert ( 
#      FileUtils.compare_file(File.join(File.dirname(__FILE__),'..','data','weather','weather_info.csv'), 
#        File.join(File.dirname(__FILE__),'weather_test.csv'))
#    )
#  end
#end

# This class will perform tests that are HDD dependant, Test model will be created
# to specifically test aspects of the NECB2011 code that are HDD dependant. 
class NECBHDDTests < Minitest::Test
  #set global variables
  NECB_epw_files_for_cdn_climate_zones = [
    'CAN_BC_Vancouver.718920_CWEC.epw',#  CZ 5 - Gas HDD = 3019 
    'CAN_ON_Toronto.716240_CWEC.epw', #CZ 6 - Gas HDD = 4088
    'CAN_PQ_Sherbrooke.716100_CWEC.epw', #CZ 7a - Electric HDD = 5068
    'CAN_YT_Whitehorse.719640_CWEC.epw', #CZ 7b - FuelOil1 HDD = 6946
    'CAN_NU_Resolute.719240_CWEC.epw' # CZ 8  -FuelOil2 HDD = 12570
  ] 


  
  # Create scaffolding to create a model with windows, then reset to appropriate values.
  # Will require large windows and constructions that have high U-values.    
  def setup()
    #Create Geometry that will be used for all tests.  
    length = 100.0; width = 100.0 ; num_above_ground_floors = 1; num_under_ground_floors = 1; floor_to_floor_height = 3.8 ; plenum_height = 1; perimeter_zone_depth = 4.57
    @model = OpenStudio::Model::Model.new
    BTAP::Geometry::Wizards::create_shape_rectangle(@model,length, width, num_above_ground_floors,num_under_ground_floors, floor_to_floor_height, plenum_height,perimeter_zone_depth )
    
    #Find all outdoor surfaces. 
    outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(@model.getSurfaces(), "Outdoors")
    @outdoor_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Wall")
    @outdoor_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "RoofCeiling")
    
    #Set all FWDR to a ratio of 0.60
    subsurfaces = []
    counter = 0
    @outdoor_walls.each {|wall| subsurfaces << wall.setWindowToWallRatio(0.60) }
    #ensure all wall subsurface types are represented. 
    subsurfaces.each do |subsurface|
      counter = counter + 1
      case counter
      when 1
        subsurface.get.setSubSurfaceType('FixedWindow')
      when 2
        subsurface.get.setSubSurfaceType('OperableWindow')
      when 3
        subsurface.get.setSubSurfaceType('Door')
      when 4
        subsurface.get.setSubSurfaceType('GlassDoor')
        counter = 0
      end
    end
    #Alternate windows to [Fixed, Operable, Door, Glass Door) 
    

    #Create skylights that are 10% of area with a 4x4m size.
    pattern = OpenStudio::Model::generateSkylightPattern(@model.getSpaces,@model.getSpaces[0].directionofRelativeNorth,0.10, 4.0, 4.0) # ratio, x value, y value
    subsurfaces = OpenStudio::Model::applySkylightPattern(pattern, @model.getSpaces, OpenStudio::Model::OptionalConstructionBase.new)
    #ensure all roof subsurface types are represented. 
    subsurfaces.each do |subsurface|
      counter = counter + 1
      case counter
      when 1
        subsurface.setSubSurfaceType('Skylight')
      when 2
        subsurface.setSubSurfaceType('TubularDaylightDome')
      when 3
        subsurface.setSubSurfaceType('TubularDaylightDiffuser')
      when 4
        subsurface.setSubSurfaceType('OverheadDoor')
        counter = 0
      end
    end

  end #setup()
  
  # Tests to ensure that the FDWR ratio is set correctly for all HDDs
  # This is not for compliance, but for archetype development.
  # NECB 2011 8.4.4 
  # @return [Bool] true if successful. 
  def test_fdwr_max()
    assert( BTAP::Geometry::get_fwdr(@model), 0.60 ) 
    BTAP::Compliance::NECB2011::set_necb_fwdr( @model, true, runner=nil)      # set FWDR   
  end #test_fdwr_max
  
  # Tests to ensure that the SRR ratio is set correctly for all HDDs
  # This is not for compliance, but for archetype development.
  # NECB 2011 8.4.4.1
  # @return [Bool] true if successful. 
  def test_srr_max()
    assert( BTAP::Geometry::get_srr(@model), 0.60 ) 
  end # test_srr_max()
  
  # Tests to ensure that the U-Values of the construction are set correctly. This 
  # test will set up  
  # for all HDDs 
  # NECB 2011 8.4.4.1
  # @return [Bool] true if successful. 
  def test_envelope()
     
    #Create report string. 
    @output = ""
    @output << "WeatherFile, outdoor_walls_average_conductance, outdoor_roofs_average_conductance , outdoor_floors_average_conductance windows_average_conductance, skylights_average_conductance , doors_average_conductance, overhead_doors_average_conductance, ground_walls_average_conductances, ground_roofs_average_conductances, ground_floors_average_conductances\n"
     
    
    #Iterate through the weather files. 
    NECB_epw_files_for_cdn_climate_zones.each do |weather_file|
    
      #Materials
      name = "opaque material";      thickness = 0.012700; conductivity = 0.160000
      opaque_mat     = BTAP::Resources::Envelope::Materials::Opaque::create_opaque_material( @model, name, thickness, conductivity)
    
      name = "insulation material";  thickness = 0.050000; conductivity = 0.043000
      insulation_mat = BTAP::Resources::Envelope::Materials::Opaque::create_opaque_material( @model,name, thickness, conductivity)
    
      name = "simple glazing test";shgc  = 0.250000 ; ufactor = 3.236460; thickness = 0.003000; visible_transmittance = 0.160000
      simple_glazing_mat = BTAP::Resources::Envelope::Materials::Fenestration::create_simple_glazing(@model,name,shgc,ufactor,thickness,visible_transmittance)
    
      name = "Standard Glazing Test"; thickness = 0.003; conductivity = 0.9; solarTransmittanceatNormalIncidence = 0.84; frontSideSolarReflectanceatNormalIncidence = 0.075; backSideSolarReflectanceatNormalIncidence = 0.075; visibleTransmittance = 0.9; frontSideVisibleReflectanceatNormalIncidence = 0.081; backSideVisibleReflectanceatNormalIncidence = 0.081; infraredTransmittanceatNormalIncidence = 0.0; frontSideInfraredHemisphericalEmissivity = 0.84; backSideInfraredHemisphericalEmissivity = 0.84; opticalDataType = "SpectralAverage"; dirt_correction_factor = 1.0; is_solar_diffusing = false
      standard_glazing_mat =BTAP::Resources::Envelope::Materials::Fenestration::create_standard_glazing( @model, name ,thickness, conductivity, solarTransmittanceatNormalIncidence, frontSideSolarReflectanceatNormalIncidence, backSideSolarReflectanceatNormalIncidence, visibleTransmittance, frontSideVisibleReflectanceatNormalIncidence, backSideVisibleReflectanceatNormalIncidence, infraredTransmittanceatNormalIncidence, frontSideInfraredHemisphericalEmissivity, backSideInfraredHemisphericalEmissivity,opticalDataType, dirt_correction_factor, is_solar_diffusing)
    
      #Constructions
      # # Surfaces 
      ext_wall                            = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionExtWall",                    [opaque_mat,insulation_mat], insulation_mat)
      ext_roof                            = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionExtRoof",                    [opaque_mat,insulation_mat], insulation_mat)
      ext_floor                           = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionExtFloor",                   [opaque_mat,insulation_mat], insulation_mat)
      grnd_wall                           = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionGrndWall",                   [opaque_mat,insulation_mat], insulation_mat)
      grnd_roof                           = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionGrndRoof",                   [opaque_mat,insulation_mat], insulation_mat)
      grnd_floor                          = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionGrndFloor",                  [opaque_mat,insulation_mat], insulation_mat)
      int_wall                            = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionIntWall",                    [opaque_mat,insulation_mat], insulation_mat)
      int_roof                            = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionIntRoof",                    [opaque_mat,insulation_mat], insulation_mat)
      int_floor                           = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionIntFloor",                   [opaque_mat,insulation_mat], insulation_mat)
      # # Subsurfaces
      fixedWindowConstruction             = BTAP::Resources::Envelope::Constructions::create_construction(@model, "FenestrationConstructionFixed",                [simple_glazing_mat])
      operableWindowConstruction          = BTAP::Resources::Envelope::Constructions::create_construction(@model, "FenestrationConstructionOperable",             [simple_glazing_mat])
      setGlassDoorConstruction            = BTAP::Resources::Envelope::Constructions::create_construction(@model, "FenestrationConstructionDoor",                 [standard_glazing_mat])
      setDoorConstruction                 = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionDoor",                       [opaque_mat,insulation_mat], insulation_mat)
      overheadDoorConstruction            = BTAP::Resources::Envelope::Constructions::create_construction(@model, "OpaqueConstructionOverheadDoor",               [opaque_mat,insulation_mat], insulation_mat)
      skylightConstruction                = BTAP::Resources::Envelope::Constructions::create_construction(@model, "FenestrationConstructionSkylight",             [standard_glazing_mat])
      tubularDaylightDomeConstruction     = BTAP::Resources::Envelope::Constructions::create_construction(@model, "FenestrationConstructionDomeConstruction",     [standard_glazing_mat])
      tubularDaylightDiffuserConstruction = BTAP::Resources::Envelope::Constructions::create_construction(@model, "FenestrationConstructionDiffuserConstruction", [standard_glazing_mat])
    
      #Construction Sets
      # # Surface
      exterior_construction_set = BTAP::Resources::Envelope::ConstructionSets::create_default_surface_constructions( @model,"ExteriorSet",ext_wall,ext_roof,ext_floor)
      interior_construction_set = BTAP::Resources::Envelope::ConstructionSets::create_default_surface_constructions( @model,"InteriorSet",int_wall,int_roof,int_floor)
      ground_construction_set   = BTAP::Resources::Envelope::ConstructionSets::create_default_surface_constructions( @model,"GroundSet",  grnd_wall,grnd_roof,grnd_floor)
    
      # # Subsurface 
      subsurface_exterior_construction_set = BTAP::Resources::Envelope::ConstructionSets::create_subsurface_construction_set( @model, fixedWindowConstruction, operableWindowConstruction, setDoorConstruction, setGlassDoorConstruction, overheadDoorConstruction, skylightConstruction, tubularDaylightDomeConstruction, tubularDaylightDiffuserConstruction)
      subsurface_interior_construction_set = BTAP::Resources::Envelope::ConstructionSets::create_subsurface_construction_set( @model, fixedWindowConstruction, operableWindowConstruction, setDoorConstruction, setGlassDoorConstruction, overheadDoorConstruction, skylightConstruction, tubularDaylightDomeConstruction, tubularDaylightDiffuserConstruction)
    
      #Default construction sets.
      name = "Construction Set 1"
      default_construction_set = BTAP::Resources::Envelope::ConstructionSets::create_default_construction_set(@model, name, exterior_construction_set, interior_construction_set, ground_construction_set, subsurface_exterior_construction_set, subsurface_interior_construction_set)

    
      #Assign default to the model. 
      @model.getBuilding.setDefaultConstructionSet( default_construction_set )
      
      #Apply NECB contruction rules. 
      @model.add_design_days_and_weather_file('HighriseApartment', 'NECB 2011', 'NECB HDD Method', weather_file)
      BTAP::Compliance::NECB2011::set_all_construction_sets_to_necb!(@model)
      
      #Get Surfaces by type.
      outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(@model.getSurfaces(), "Outdoors")
      outdoor_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Wall")
      outdoor_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "RoofCeiling")
      outdoor_floors = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Floor")
      outdoor_subsurfaces = BTAP::Geometry::Surfaces::get_subsurfaces_from_surfaces(outdoor_surfaces)
      windows = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["FixedWindow" , "OperableWindow" ])
      skylights = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["Skylight", "TubularDaylightDiffuser","TubularDaylightDome" ])
      doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["Door" , "GlassDoor" ])
      overhead_doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["OverheadDoor" ])
      ground_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(@model.getSurfaces(), "Ground")
      ground_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "Wall")
      ground_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "RoofCeiling")
      ground_floors = BTAP::Geometry::Surfaces::filter_by_surface_types(ground_surfaces, "Floor")
      
      #Determine the weighted average conductances by surface type. 
      outdoor_walls_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(outdoor_walls)
      outdoor_roofs_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(outdoor_roofs)
      outdoor_floors_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(outdoor_floors)
      windows_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(windows)
      skylights_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(skylights)
      doors_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(doors)
      overhead_doors_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(overhead_doors)
      ground_walls_average_conductances = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(ground_walls)
      ground_roofs_average_conductances = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(ground_roofs)
      ground_floors_average_conductances = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(ground_floors)

      #Save information to report. 
      @output << "#{weather_file}, #{outdoor_walls_average_conductance}, #{outdoor_roofs_average_conductance} , #{outdoor_floors_average_conductance} #{windows_average_conductance}, #{skylights_average_conductance} , #{doors_average_conductance}, #{overhead_doors_average_conductance}, #{ground_walls_average_conductances}, #{ground_roofs_average_conductances}, #{ground_floors_average_conductances}\n"
      
      
      
      
      BTAP::FileIO::save_osm(@model, 'c:/test/phylroy.osm')
    end #Weather file loop.
    puts @output
    
  end # test_envelope()
      
      
    
    
end #Class NECBHDDTests
  

  


# This class will perform tests that are Spacetype dependant, Test model will be created
# to specifically test aspects of the NECB2011 code that are Spacetype dependant. 
class NECB2011SpaceTypeTests < Minitest::Test
  
  # Tests to ensure that the NECB default schedules are being defined correctly.
  # This is not for compliance, but for archetype development. 
  # @return [Bool] true if successful. 
  def schedule_type_defaults_test()
    
  end
  # This test will ensure that the wildcard spacetypes are being assigned the 
  # appropriate schedule.
  # This is not for compliance, but for archetype development. 
  # @return [Bool] true if successful. 
  def wildcard_schedule_defaults_test()
    
  end
  
  # This test will ensure that the loads for each of the 133 spacetypes are 
  # being assigned the appropriate values for SHW, People and Equipment.
  # This is not for compliance, but for archetype development. 
  # @return [Bool] true if successful. 
  def internal_loads_test()
    
  end
  
  # This test will ensure that the loads for each of the 133 spacetypes are 
  # being assigned the appropriate values for LPD.
  # This is not for compliance, but for archetype development. 
  # @return [Bool] true if successful.
  def lighting_power_density_test()
    
  end
  
  
  # This test will ensure that the system selection for each of the 133 spacetypes are 
  # being assigned the appropriate values for LPD.
  # @return [Bool] true if successful.
  def system_selection_test()
    
  end
  
  
end




