extends SceneTree

## P1 校验：构建棋盘拓扑并核对规模与度数分布。
## 用法： godot --headless --path . --script res://tools/verify_topology.gd
## 退出码 0 = 通过，1 = 失败。

func _initialize() -> void:
	var topo := BoardTopology.instance()
	print("=== 棋盘拓扑自检 ===")
	print("地块 hex     : %d" % topo.hexes.size())
	print("顶点 vertex  : %d" % topo.vertices.size())
	print("边   edge    : %d" % topo.edges.size())

	var deg_dist := {}
	for vh in topo.vertex_hexes:
		deg_dist[vh.size()] = deg_dist.get(vh.size(), 0) + 1
	print("顶点相邻地块数分布 : %s" % [deg_dist])

	var edge_dist := {}
	for eh in topo.edge_hexes:
		edge_dist[eh.size()] = edge_dist.get(eh.size(), 0) + 1
	print("边相邻地块数分布   : %s" % [edge_dist])

	# 连通性：从顶点 0 出发应能走遍全部 54 个顶点
	var seen := {}
	var stack := [0]
	while not stack.is_empty():
		var v: int = stack.pop_back()
		if seen.has(v):
			continue
		seen[v] = true
		for n in topo.vertex_neighbors[v]:
			if not seen.has(n):
				stack.append(n)
	print("顶点图连通分量覆盖 : %d / %d" % [seen.size(), topo.vertices.size()])

	var errs := topo.self_check()
	if not errs.is_empty():
		print("!!! 拓扑校验失败:")
		for e in errs:
			print("   - " + e)
		quit(1)
		return

	if seen.size() != topo.vertices.size():
		print("!!! 顶点图不连通")
		quit(1)
		return

	print("TOPOLOGY OK")
	quit(0)
