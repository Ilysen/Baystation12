// Keeps tabs on every client currently in VR, as well as every occupant and very virtual mob.
// If an occupant is no longer valid in VR (i.e. pod depowered), it will yank them out and put them into their original mob.
SUBSYSTEM_DEF(virtual_reality)
	name = "VR"
	priority = SS_PRIORITY_VR
	init_order = SS_INIT_DEFAULT
	wait = 0.5 SECONDS
	
	var/list/virtual_mobs_to_occupants = list()		// Associative list of /mob/living => /mob/living. Each virtual mob is tied to its occupant.
	var/list/virtual_occupants_to_mobs = list()		// Reverse of previous list, in case one is missing but not the other.
	var/list/virtual_clients = list()				// Associative list of /client => /mob/living. Each client is linked to its virtual mob.

/datum/controller/subsystem/virtual_reality/fire(resumed = FALSE)
	for (var/mob/living/L in virtual_occupants_to_mobs)
		if (!check_vr(L))
			remove_virtual_mob(L)

// Checks whether or not the provided occupant can remain inside of VR. Returns TRUE or FALSE.
/datum/controller/subsystem/virtual_reality/proc/check_vr(mob/living/user)
	var/is_valid = FALSE
	var/obj/machinery/vr_pod/pod = user.loc
	if (istype(pod)) // Check for powered and operable VR pod
		is_valid = pod.is_powered() && pod.operable()
	return is_valid

// Creates a virtual mob for the provided occupant. Humans will take appearance based on client prefs.
// Returns the instance of the mob that was created.
/datum/controller/subsystem/virtual_reality/proc/create_virtual_mob(mob/living/new_occupant, mob_type)
	var/mob/living/simulated_mob = new mob_type(get_turf(new_occupant))
	if (ishuman(simulated_mob) && ishuman(new_occupant)) // Copy human appearance for the new mob
		var/mob/living/carbon/human/H = simulated_mob
		new_occupant.client.prefs.copy_to(simulated_mob)
		H.set_nutrition(400)
		H.set_hydration(400)
		for (var/obj/item/I in H)
			if (istype(I, /obj/item/underwear))
				I.canremove = FALSE
				I.verbs -= /obj/item/underwear/verb/RemoveSocks
	log_and_message_admins("entered VR as [simulated_mob].", new_occupant)

	var/datum/extension/virtual_mob/VM = get_or_create_extension(simulated_mob, /datum/extension/virtual_mob)
	VM.set_mob(simulated_mob, src)

	virtual_occupants_to_mobs[new_occupant] = simulated_mob
	virtual_mobs_to_occupants[simulated_mob] = new_occupant
	virtual_clients[new_occupant.client] = simulated_mob

	new_occupant.mind.transfer_to(simulated_mob)
	return simulated_mob

// Removes a mob from VR. Accepts both occupants and virtual mobs as a first argument.
// Returns TRUE if the removal succeeded.
/datum/controller/subsystem/virtual_reality/proc/remove_virtual_mob(mob/living/removed_mob, silent = FALSE)
	var/mob/living/occ_mob = null
	var/mob/living/vir_mob = null

	if (virtual_occupants_to_mobs[removed_mob])
		occ_mob = removed_mob
		vir_mob = virtual_occupants_to_mobs[removed_mob]
	else if (virtual_mobs_to_occupants[removed_mob])
		occ_mob = virtual_mobs_to_occupants[removed_mob]
		vir_mob = removed_mob

	if (!occ_mob || !vir_mob)
		return FALSE

	var/client/C = virtual_clients[vir_mob.client]
	if (!C)
		return FALSE
		
	virtual_occupants_to_mobs -= occ_mob
	virtual_mobs_to_occupants -= vir_mob
	virtual_clients -= C

	if (!silent)
		to_chat(vir_mob, SPAN_NOTICE("Your view blurs and distorts for a moment, and you feel weightless. And then, you're back in reality."))
		vir_mob.visible_message(SPAN_NOTICE("\The [vir_mob] visibly pixelates, and then fades away."))

	for(var/obj/item/W in vir_mob)
		if (W.canremove)
			vir_mob.drop_from_inventory(W)
	
	vir_mob.mind.transfer_to(occ_mob)
	QDEL_NULL(vir_mob)
	return TRUE
