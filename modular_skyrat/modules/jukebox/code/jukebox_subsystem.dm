/// Maximum jukebox volume in percent
#define JUKEBOX_VOLUME_MAX 85

SUBSYSTEM_DEF(jukeboxes)
	name = "Jukeboxes"
	wait = 5
	var/list/songs = list()
	var/list/activejukeboxes = list()
	var/list/freejukeboxchannels = list()

/datum/track
	var/song_artist = "Unknown Artist"
	var/song_title = "Unknown Title"
	var/song_path = null
	var/song_length = 0
	var/song_beat = 0

/datum/track/New(artist, title, path, length, beat)
	song_artist = artist
	song_title = title
	song_path = path
	song_length = length
	song_beat = beat

/**
 * Clear the tracklist and load songs from disk into the subsystem
 */
/datum/controller/subsystem/jukeboxes/proc/reload_tracks()
	// We're *re*loading the tracklist, so remove everything
	songs.Cut()

	// Now we just add new tracks
	load_tracks()

/**
 * Load songs from disk into the subsystem, only adding new
 */
/datum/controller/subsystem/jukeboxes/proc/load_tracks()
	var/list/tracks_to_load = flist("[global.config.directory]/jukebox_music/sounds/")

	for(var/song_file in tracks_to_load)
		var/datum/track/track = new()
		track.song_path = file("[global.config.directory]/jukebox_music/sounds/[song_file]")
		var/list/song_data = splittext(song_file,"+")
		if(song_data.len != 4)
			continue
		track.song_artist = song_data[1]
		track.song_title = song_data[2]
		track.song_length = (text2num(song_data[3]) SECONDS)
		track.song_beat = ((text2num(song_data[4]) / 60) SECONDS)
		songs |= track

/datum/controller/subsystem/jukeboxes/proc/addjukebox(obj/machinery/jukebox/jukebox, datum/track/T, jukefalloff = 1)
	if(!istype(T))
		CRASH("[src] tried to play a song with a nonexistant track")
	var/channeltoreserve = pick(freejukeboxchannels)
	if(!channeltoreserve)
		return FALSE
	freejukeboxchannels -= channeltoreserve
	var/list/youvegotafreejukebox = list(T, channeltoreserve, jukebox, jukefalloff)
	activejukeboxes.len++
	activejukeboxes[activejukeboxes.len] = youvegotafreejukebox

	//Due to changes in later versions of 512, SOUND_UPDATE no longer properly plays audio when a file is defined in the sound datum. As such, we are now required to init the audio before we can actually do anything with it.
	//Downsides to this? This means that you can *only* hear the jukebox audio if you were present on the server when it started playing, and it means that it's now impossible to add loops to the jukebox track list.
	var/sound/song_to_init = sound(T.song_path)
	song_to_init.status = SOUND_MUTE
	for(var/mob/M in GLOB.player_list)
		if(!M.client)
			continue
		if(!(M.client.prefs.read_preference(/datum/preference/toggle/sound_instruments)))
			continue

		M.playsound_local(M, null, jukebox.volume, channel = youvegotafreejukebox[2], sound_to_use = song_to_init)
	return activejukeboxes.len

/datum/controller/subsystem/jukeboxes/proc/removejukebox(IDtoremove)
	if(islist(activejukeboxes[IDtoremove]))
		var/jukechannel = activejukeboxes[IDtoremove][2]
		for(var/mob/M in GLOB.player_list)
			if(!M.client)
				continue
			M.stop_sound_channel(jukechannel)
		freejukeboxchannels |= jukechannel
		activejukeboxes.Cut(IDtoremove, IDtoremove+1)
		return TRUE
	else
		CRASH("Tried to remove jukebox with invalid ID")

/datum/controller/subsystem/jukeboxes/proc/findjukeboxindex(obj/machinery/jukebox)
	if(activejukeboxes.len)
		for(var/list/jukeinfo in activejukeboxes)
			if(jukebox in jukeinfo)
				return activejukeboxes.Find(jukeinfo)
	return FALSE

/datum/controller/subsystem/jukeboxes/Initialize()
	load_tracks()

	for(var/i in CHANNEL_JUKEBOX_START to CHANNEL_JUKEBOX)
		freejukeboxchannels |= i
	return SS_INIT_SUCCESS

/datum/controller/subsystem/jukeboxes/fire()
	if(!activejukeboxes.len)
		return
	for(var/list/jukeinfo in activejukeboxes)
		if(!jukeinfo.len)
			stack_trace("Active jukebox without any associated metadata.")
			continue
		var/datum/track/juketrack = jukeinfo[1]
		if(!istype(juketrack))
			stack_trace("Invalid jukebox track datum.")
			continue
		var/obj/machinery/jukebox/jukebox = jukeinfo[3]
		if(!istype(jukebox))
			stack_trace("Nonexistant or invalid object associated with jukebox.")
			continue
		var/sound/song_played = sound(juketrack.song_path)
		var/turf/currentturf = get_turf(jukebox)

		song_played.falloff = jukeinfo[4]

		for(var/mob/M in GLOB.player_list)
			if(!M.client)
				continue
			if(!(M.client.prefs.read_preference(/datum/preference/toggle/sound_instruments)) || !M.can_hear())
				M.stop_sound_channel(jukeinfo[2])
				continue

			if(jukebox.z == M.z)	//todo - expand this to work with mining planet z-levels when robust jukebox audio gets merged to master
				song_played.status = SOUND_UPDATE
			else
				song_played.status = SOUND_MUTE | SOUND_UPDATE	//Setting volume = 0 doesn't let the sound properties update at all, which is lame.

			var/real_jukebox_volume = (jukebox.volume * (JUKEBOX_VOLUME_MAX / 100))

			M.playsound_local(currentturf, null, real_jukebox_volume, channel = jukeinfo[2], sound_to_use = song_played)
			CHECK_TICK
	return

#undef JUKEBOX_VOLUME_MAX
