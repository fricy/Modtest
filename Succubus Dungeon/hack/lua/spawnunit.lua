--create unit at pointer or given location and with given civ (usefull to pass -1 for enemy). Usage e.g. "spawnunit DWARF 0 Dwarfy"
--[=[
    This is the library version, designed for mod devs who want to create scripts that spawns and manipulate creatures.

    Usage:
    - You must first feed the library params for your future creature.
    - Adding race (with setRace) is mandatory.
    - If no position is set, it will try to use the cursor position or otherwise fail.
    - Then you execute your spawn using place(num) where num is the number od creatures spawned.
    - The created unit(s) are returned in an array.
    - The params are reset after spawning a creature.

    Variables :
    - name: The name of your creature or nil if you do not want a name
    - race: The RAW_ID of the creature's race, mandatory
    - pos: A position in a {x, y, z} form
    - civ_id: The creature's civ number, nil for friendly to the player, -1 for hostile
    - caste: A caste number, or nil for random
    - amount: the number of copies you wish to creature, defaults to 1

    Method :
    - setPos: converts and register a positions array (ie the result of {dfhack.units.getPosition(unit)})
    - reset: Rests the variables to their defaults
    - place: Spawns the unit(s)

    Examples:

    local spawnunit = require 'spawnunit'

    -- Spawns 5 dogs at their master's pos, gender is random
    spawnunit.race = 'DOG'
    spawnunit.setPost({dfhack.units.getPosition(unitMaster)})
    spawnunit.amount = 5
    unitDogs = spawnunit.place()
    
    spawnunit.reset()

    -- Spawn a female duck named ducky at the cursor
    spawnunit.race = 'DUCK'
    spawnunit.caste = 1
    spawnunit.name = 'Ducky'
    duck = spawnunit.place()

    spawnunit.reset()

    -- Spawn an hostile goblin at the cursor
    spawnunit.race = 'GOBLIN'
    spawnunit.civ_id = -1
    spawnunit.place()

    Made by warmist, but edited by Putnam for the dragon ball mod to be used in reactions
    Converted into a weird library by Boltgun
    TODO:
        orientation
        chosing a caste based on ratios
        birth time
        death time
        real body size
        blood max
        check if soulless and skip make soul
        set weapon body part
        nemesis/histfig : add an 'arrived on site' event
        generate name
--]=]
local _ENV = mkmodule('spawnunit')

local utils=require 'utils'

-- Picking a caste or gender at random
local function getRandomCasteId(race_id)
    local cr = df.creature_raw.find(race_id)
    local caste_id, casteMax

    casteMax = #cr.caste - 1

    if casteMax > 0 then
        return math.random(0, casteMax)
    end

    return 0
end

function getCaste(race_id,caste_id)
    local cr=df.creature_raw.find(race_id)
    return cr.caste[caste_id]
end
function genBodyModifier(body_app_mod)
    local a=math.random(0,#body_app_mod.ranges-2)
    return math.random(body_app_mod.ranges[a],body_app_mod.ranges[a+1])
end
function getBodySize(caste,time)
    --TODO: real body size...
    return caste.body_size_1[#caste.body_size_1-1] --returns last body size
end
function genAttribute(array)
    local a=math.random(0,#array-2)
    return math.random(array[a],array[a+1])
end
function norm()
    return math.sqrt((-2)*math.log(math.random()))*math.cos(2*math.pi*math.random())
end
function normalDistributed(mean,sigma)
    return mean+sigma*norm()
end
function clampedNormal(min,median,max)
    local val=normalDistributed(median,math.sqrt(max-min))
    if val<min then return min end
    if val>max then return max end
    return val
end
function makeSoul(unit,caste)
    local tmp_soul=df.unit_soul:new()
    tmp_soul.unit_id=unit.id
    tmp_soul.name:assign(unit.name)
    tmp_soul.race=unit.race
    tmp_soul.sex=unit.sex
    tmp_soul.caste=unit.caste
    --todo: preferences,traits.
    local attrs=caste.attributes
    for k,v in pairs(attrs.ment_att_range) do
       local max_percent=attrs.ment_att_cap_perc[k]/100
       local cvalue=genAttribute(v)
       tmp_soul.mental_attrs[k]={value=cvalue,max_value=cvalue*max_percent}
    end
    for k,v in pairs(tmp_soul.personality.traits) do
        local min,mean,max
        min=caste.personality.a[k]
        mean=caste.personality.b[k]
        max=caste.personality.c[k]
        tmp_soul.personality.traits[k]=clampedNormal(min,mean,max)
    end
    --[[natural skill fix]]
    for k, skill in ipairs(caste.natural_skill_id) do
        local rating = caste.natural_skill_lvl[k]
        utils.insert_or_update(tmp_soul.skills,
            {new=true,id=skill,experience=caste.natural_skill_exp[k],rating=rating}, 'id')
    end
    
    unit.status.souls:insert("#",tmp_soul)
    unit.status.current_soul=tmp_soul
end
function CreateUnit(race_id,caste_id)
    local race=df.creature_raw.find(race_id)
    if race==nil then error("Invalid race_id") end
    local caste
    local unit=df.unit:new()

    -- Pick a random caste is none are set
    if nil == caste_id then
        caste_id = getRandomCasteId(race_id)
    end

    caste = getCaste(race_id, caste_id)

    unit:assign{
        race=race_id,
        caste=caste_id,
        sex=caste.gender,
    }

    unit.relations.birth_year=df.global.cur_year-15 --AGE is set here
    if caste.misc.maxage_max==-1 then
        unit.relations.old_year=-1
    else
        unit.relations.old_year=df.global.cur_year+math.random(caste.misc.maxage_min,caste.misc.maxage_max)
    end
    
    --unit.relations.birth_time=??
    --unit.relations.old_time=?? --TODO add normal age
    --[[ interataction stuff, probably timers ]]--
    local num_inter=#caste.body_info.interactions  -- new for interactions
    unit.curse.own_interaction:resize(num_inter) -- new for interactions
    unit.curse.own_interaction_delay:resize(num_inter) -- new for interactions
    --[[ body stuff ]]
    
    local body=unit.body
    body.body_plan=caste.body_info
    local body_part_count=#body.body_plan.body_parts
    local layer_count=#body.body_plan.layer_part
    --[[ body components ]]
    local cp=body.components
    cp.body_part_status:resize(body_part_count)
    cp.numbered_masks:resize(#body.body_plan.numbered_masks)
    for num,v in ipairs(body.body_plan.numbered_masks) do
        cp.numbered_masks[num]=v
    end
    cp.layer_status:resize(layer_count)
    cp.layer_wound_area:resize(layer_count)
    cp.layer_cut_fraction:resize(layer_count)
    cp.layer_dent_fraction:resize(layer_count)
    cp.layer_effect_fraction:resize(layer_count)
    
    local attrs=caste.attributes
    for k,v in pairs(attrs.phys_att_range) do
        local max_percent=attrs.phys_att_cap_perc[k]/100
        local cvalue=genAttribute(v)
        unit.body.physical_attrs[k]={value=cvalue,max_value=cvalue*max_percent}
    end
 
    
    body.blood_max=getBodySize(caste,0) --TODO normal values
    body.blood_count=body.blood_max
    body.infection_level=0
    unit.status2.body_part_temperature:resize(body_part_count)
    for k,v in pairs(unit.status2.body_part_temperature) do
        unit.status2.body_part_temperature[k]={new=true,whole=10067,fraction=0}
        
    end
    --[[ largely unknown stuff ]]
    local stuff=unit.enemy
    stuff.body_part_878:resize(body_part_count) -- all = 3
    stuff.body_part_888:resize(body_part_count) -- all = 3
    stuff.body_part_relsize:resize(body_part_count) -- all =0
    
    stuff.were_race=race_id
    stuff.were_caste=caste_id
    stuff.normal_race=race_id
    stuff.normal_caste=caste_id
    stuff.body_part_8a8:resize(body_part_count) -- all = 1
    stuff.body_part_base_ins:resize(body_part_count) 
    stuff.body_part_clothing_ins:resize(body_part_count) 
    stuff.body_part_8d8:resize(body_part_count)
    
    --TODO add correct sizes. (calculate from age)
    local size=caste.body_size_2[#caste.body_size_2-1]
    body.size_info.size_cur=size
    body.size_info.size_base=size
    body.size_info.area_cur=math.pow(size,0.666)
    body.size_info.area_base=math.pow(size,0.666)
    body.size_info.area_cur=math.pow(size*10000,0.333)
    body.size_info.area_base=math.pow(size*10000,0.333)
    
    unit.recuperation.healing_rate:resize(layer_count) 
    
    --appearance
    local app=unit.appearance
    app.body_modifiers:resize(#caste.body_appearance_modifiers) --3
    for k,v in pairs(app.body_modifiers) do
        app.body_modifiers[k]=genBodyModifier(caste.body_appearance_modifiers[k])
    end
    app.bp_modifiers:resize(#caste.bp_appearance.modifier_idx) --0
    for k,v in pairs(app.bp_modifiers) do
        app.bp_modifiers[k]=genBodyModifier(caste.bp_appearance.modifiers[caste.bp_appearance.modifier_idx[k]])
    end
    --app.unk_4c8:resize(33)--33
    app.tissue_style:resize(#caste.bp_appearance.style_part_idx)
    app.tissue_style_civ_id:resize(#caste.bp_appearance.style_part_idx)
    app.tissue_style_id:resize(#caste.bp_appearance.style_part_idx)
    app.tissue_style_type:resize(#caste.bp_appearance.style_part_idx)
    app.tissue_length:resize(#caste.bp_appearance.style_part_idx)
    app.genes.appearance:resize(#caste.body_appearance_modifiers+#caste.bp_appearance.modifiers) --3
    app.genes.colors:resize(#caste.color_modifiers*2) --???
    app.colors:resize(#caste.color_modifiers)--3
    
    makeSoul(unit,caste)
    
    --finally set the id
    unit.id=df.global.unit_next_id
    df.global.unit_next_id=df.global.unit_next_id+1
    df.global.world.units.all:insert("#",unit)
    df.global.world.units.active:insert("#",unit)
    
    return unit
end
function findRace(name)
    for k,v in pairs(df.global.world.raws.creatures.all) do
        if v.creature_id==name then
            return k
        end
    end
    qerror("Race:"..name.." not found!")
end
 
function createFigure(trgunit,he,he_group)
    local hf=df.historical_figure:new()
    hf.id=df.global.hist_figure_next_id
    hf.race=trgunit.race
    hf.caste=trgunit.caste
    hf.profession = trgunit.profession
    hf.sex = trgunit.sex
    df.global.hist_figure_next_id=df.global.hist_figure_next_id+1
    hf.appeared_year = df.global.cur_year
    
    hf.born_year = trgunit.relations.birth_year
    hf.born_seconds = trgunit.relations.birth_time
    hf.curse_year = trgunit.relations.curse_year
    hf.curse_seconds = trgunit.relations.curse_time
    hf.birth_year_bias = trgunit.relations.birth_year_bias
    hf.birth_time_bias = trgunit.relations.birth_time_bias
    hf.old_year = trgunit.relations.old_year
    hf.old_seconds = trgunit.relations.old_time
    hf.died_year = -1
    hf.died_seconds = -1
    hf.name:assign(trgunit.name)
    hf.civ_id = trgunit.civ_id
    hf.population_id = trgunit.population_id
    hf.breed_id = -1
    hf.unit_id = trgunit.id
    
    df.global.world.history.figures:insert("#",hf)
 
    hf.info = df.historical_figure_info:new()
    hf.info.unk_14 = df.historical_figure_info.T_unk_14:new() -- hf state?
    --unk_14.region_id = -1; unk_14.beast_id = -1; unk_14.unk_14 = 0
    hf.info.unk_14.unk_18 = -1; hf.info.unk_14.unk_1c = -1
    -- set values that seem related to state and do event
    --change_state(hf, dfg.ui.site_id, region_pos)
 
 
    --lets skip skills for now
    --local skills = df.historical_figure_info.T_skills:new() -- skills snap shot
    -- ...
    hf.info.skills = {new=true}
 
 
    he.histfig_ids:insert('#', hf.id)
    he.hist_figures:insert('#', hf)
    if he_group then
        he_group.histfig_ids:insert('#', hf.id)
        he_group.hist_figures:insert('#', hf)
        hf.entity_links:insert("#",{new=df.histfig_entity_link_memberst,entity_id=he_group.id,link_strength=100})
    end
    trgunit.flags1.important_historical_figure = true
    trgunit.flags2.important_historical_figure = true
    trgunit.hist_figure_id = hf.id
    trgunit.hist_figure_id2 = hf.id
    
    hf.entity_links:insert("#",{new=df.histfig_entity_link_memberst,entity_id=trgunit.civ_id,link_strength=100})
    
    --add entity event
    local hf_event_id=df.global.hist_event_next_id
    df.global.hist_event_next_id=df.global.hist_event_next_id+1
    df.global.world.history.events:insert("#",{new=df.history_event_add_hf_entity_linkst,year=trgunit.relations.birth_year,
    seconds=trgunit.relations.birth_time,id=hf_event_id,civ=hf.civ_id,histfig=hf.id,link_type=0})
    return hf
end
function  allocateNewChunk(hist_entity)
    hist_entity.save_file_id=df.global.unit_chunk_next_id
    df.global.unit_chunk_next_id=df.global.unit_chunk_next_id+1
    hist_entity.next_member_idx=0
    print("allocating chunk:",hist_entity.save_file_id)
end
function allocateIds(nemesis_record,hist_entity)
    if hist_entity.next_member_idx==100 then
        allocateNewChunk(hist_entity)
    end
    nemesis_record.save_file_id=hist_entity.save_file_id
    nemesis_record.member_idx=hist_entity.next_member_idx
    hist_entity.next_member_idx=hist_entity.next_member_idx+1
end
 
function createNemesis(trgunit,civ_id,group_id)
    local id=df.global.nemesis_next_id
    local nem=df.nemesis_record:new()
    
    nem.id=id
    nem.unit_id=trgunit.id
    nem.unit=trgunit
    nem.flags:resize(4)
    --not sure about these flags...
    -- [[
    nem.flags[4]=true
    nem.flags[5]=true
    nem.flags[6]=true
    nem.flags[7]=true
    nem.flags[8]=true
    nem.flags[9]=true
    --]]
    --[[for k=4,8 do
        nem.flags[k]=true
    end]]
    nem.unk10=-1
    nem.unk11=-1
    nem.unk12=-1
    df.global.world.nemesis.all:insert("#",nem)
    df.global.nemesis_next_id=id+1
    trgunit.general_refs:insert("#",{new=df.general_ref_is_nemesisst,nemesis_id=id})
    trgunit.flags1.important_historical_figure=true
    
    nem.save_file_id=-1
 
    local he=df.historical_entity.find(civ_id)
    he.nemesis_ids:insert("#",id)
    he.nemesis:insert("#",nem)
    local he_group
    if group_id~=-1 then
        he_group=df.historical_entity.find(group_id)
    end
    if he_group then
        he_group.nemesis_ids:insert("#",id)
        he_group.nemesis:insert("#",nem)
    end
    allocateIds(nem,he)
    nem.figure=createFigure(trgunit,he,he_group)
end

-- Params
position, civ_id, caste, race, name = nil
no_nemesis = false
amount = 1

function reset()
    name = nil
    pos = nil
    civ_id = nil
    caste = nil
    amount = 1
end

function setPos(posArray)
    position = {}
    position.x = posArray[1]
    position.y = posArray[2]
    position.z = posArray[3]
end
 
-- Do the placement, race must be set, returns the created units
function place()

    local race_id = findRace(race)

    local pos = position or copyall(df.global.cursor)
    local i

    if pos.x==-30000 then
        qerror("Point your pointy thing somewhere")
    end

    if not race then
        qerror('Please assign a value to race first')
    end

    local race = findRace(race)
    local units = {}

    for i = 1,amount do
        local u = CreateUnit(race, caste)

        u.pos:assign(pos)
            
        if name then
            u.name.first_name = name
            u.name.has_name = true
        end

        local group_id
        if df.global.gamemode == df.game_mode.ADVENTURE then
            u.civ_id = civ_id or df.global.world.units.active[0].civ_id
            group_id = -1
        else    
            u.civ_id = civ_id or df.global.ui.civ_id
        end

        if civ_id == -1 then
            group_id = group_id or -1
        else
            group_id = group_id or df.global.ui.group_id
        end

        local desig,ocupan = dfhack.maps.getTileFlags(pos)
        if ocupan.unit then
            ocupan.unit_grounded = true
            u.flags1.on_ground = true
        else
            ocupan.unit = true
        end

        units[i] = u

        if not no_nemesis and df.historical_entity.find(u.civ_id) ~= nil  then
            createNemesis(u,u.civ_id,group_id)
        end
    end
    
    reset()

    return units
end

return _ENV
