extends RefCounted
## 碰撞 RID 收集工具：递归收集节点子树所有 CollisionObject3D 的 RID（射线排除用）。
## 供 OcclusionShatter / PlayerController / HD2DCharacter 等共享，避免重复实现。
## ⚠️ 无 class_name：调用方用 preload 常量引用，避免与全局类同名产生 SHADOWED 警告。

## 收集指定组内所有节点的碰撞体 RID（含子树递归）。
static func collect_group_rids(tree: SceneTree, group: String) -> Array[RID]:
	var rids: Array[RID] = []
	for node in tree.get_nodes_in_group(group):
		append_collision_rids(node, rids)
	return rids


## 递归收集 node 子树所有 CollisionObject3D 的 RID。
static func append_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		var rid := (node as CollisionObject3D).get_rid()
		if rid.is_valid():
			rids.append(rid)
	for child in node.get_children():
		append_collision_rids(child, rids)
