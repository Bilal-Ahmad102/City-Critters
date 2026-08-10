class_name WaypointNetwork extends Node3D
# A manual navigation graph built from Marker3D children (waypoints laid along
# the roads). NPCs route over it to pick a high-level path, then walk each hop
# with their own NavigationAgent3D/navmesh (hybrid routing).
#
# Edges are built automatically: two waypoints are connected when they are within
# `max_edge_distance` of each other AND the straight segment between them is clear
# of building colliders (a horizontal raycast on `obstacle_mask`). That keeps
# edges running along open roads instead of cutting diagonally through a block.
#
# Attach this to the node that holds the Marker3D waypoints (the "Waypoints" node
# in Town_Scene.scn). It self-registers in the "waypoint_network" group; NPCs find
# it there and call route().

## Longest straight connection allowed between two waypoints.
@export var max_edge_distance: float = 35.0
## Physics layers that count as obstacles when validating an edge (buildings are on layer 1).
@export_flags_3d_physics var obstacle_mask: int = 1
## Height above the waypoint at which the clear-check ray is cast (chest height, so it
## clears curbs and the ground but still hits walls).
@export var ray_height: float = 1.0
## Print the edge count / connectivity once the graph is built.
@export var debug_report: bool = false

var _points: PackedVector3Array = PackedVector3Array()
var _adj: Array = []  # _adj[i] = Array of { "to": int, "cost": float }
var _built: bool = false


func _ready() -> void:
	add_to_group("waypoint_network")
	# Warm up the graph a couple of frames in (once colliders/physics exist), but
	# route() also builds on demand so an NPC that asks earlier never races it.
	call_deferred("_build")


func _build() -> void:
	if _built:
		return

	_points = PackedVector3Array()
	for c in get_children():
		if c is Marker3D:
			_points.append((c as Marker3D).global_position)

	_adj = []
	_adj.resize(_points.size())
	for i in _points.size():
		_adj[i] = []

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var edges: int = 0
	for i in _points.size():
		for j in range(i + 1, _points.size()):
			var d: float = _points[i].distance_to(_points[j])
			if d > max_edge_distance:
				continue
			if _segment_clear(space, _points[i], _points[j]):
				(_adj[i] as Array).append({"to": j, "cost": d})
				(_adj[j] as Array).append({"to": i, "cost": d})
				edges += 1

	_built = true
	if debug_report:
		var isolated: int = 0
		for i in _points.size():
			if (_adj[i] as Array).is_empty():
				isolated += 1
		print("WaypointNetwork: %d waypoints, %d edges, %d isolated." % [_points.size(), edges, isolated])


func _segment_clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var from: Vector3 = a + Vector3.UP * ray_height
	var to: Vector3 = b + Vector3.UP * ray_height
	var q := PhysicsRayQueryParameters3D.create(from, to, obstacle_mask)
	return space.intersect_ray(q).is_empty()


# Ordered waypoint positions to travel from `from` to `to`: the shortest path
# across the graph, start waypoint first, goal waypoint last. Empty when there is
# no graph, no reachable path, or both ends map to the same waypoint (go direct).
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _built:
		_build()  # build on demand so the first NPC to ask never races the deferred build
	if _points.is_empty():
		return PackedVector3Array()
	var s: int = _nearest(from)
	var g: int = _nearest(to)
	if s == -1 or g == -1 or s == g:
		return PackedVector3Array()

	var n: int = _points.size()
	var dist: PackedFloat32Array = PackedFloat32Array()
	var prev: PackedInt32Array = PackedInt32Array()
	dist.resize(n)
	prev.resize(n)
	for i in n:
		dist[i] = INF
		prev[i] = -1
	dist[s] = 0.0

	# Dijkstra. Only 33 nodes, so a linear-scan frontier is plenty.
	var visited: Dictionary = {}
	while true:
		var u: int = -1
		var best: float = INF
		for i in n:
			if not visited.has(i) and dist[i] < best:
				best = dist[i]
				u = i
		if u == -1 or u == g:
			break
		visited[u] = true
		for e in (_adj[u] as Array):
			var to_i: int = e["to"]
			var nd: float = dist[u] + float(e["cost"])
			if nd < dist[to_i]:
				dist[to_i] = nd
				prev[to_i] = u

	if dist[g] == INF:
		return PackedVector3Array()  # start and goal are in disconnected components

	# Backtrack from the destination waypoint to the NPC's, then reverse to walk order.
	var chain: PackedInt32Array = PackedInt32Array()
	var c: int = g
	while c != -1:
		chain.append(c)
		if c == s:
			break
		c = prev[c]
	chain.reverse()

	var out: PackedVector3Array = PackedVector3Array()
	for idx in chain:
		out.append(_points[idx])
	return out


func _nearest(p: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i in _points.size():
		var d: float = p.distance_to(_points[i])
		if d < best_d:
			best_d = d
			best = i
	return best
