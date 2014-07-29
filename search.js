"use strict";
var items = [
{"std.allocator.stateSize" : "std/allocator.stateSize.html"},
{"std.allocator.allocate" : "std/allocator.allocate.html"},
{"std.allocator.allocate" : "std/allocator.allocate.html"},
{"std.allocator.deallocate" : "std/allocator.deallocate.html"},
{"std.allocator.deallocate" : "std/allocator.deallocate.html"},
{"containers.treemap.TreeMap" : "containers/treemap.TreeMap.html"},
{"containers.treemap.TreeMap.opIndexAssign" : "containers/treemap.TreeMap.opIndexAssign.html"},
{"containers.treemap.TreeMap.opIndex" : "containers/treemap.TreeMap.opIndex.html"},
{"containers.treemap.TreeMap.remove" : "containers/treemap.TreeMap.remove.html"},
{"containers.treemap.TreeMap.containsKey" : "containers/treemap.TreeMap.containsKey.html"},
{"containers.treemap.TreeMap.empty" : "containers/treemap.TreeMap.empty.html"},
{"containers.treemap.TreeMap.length" : "containers/treemap.TreeMap.length.html"},
{"containers.treemap.TreeMap.opApply" : "containers/treemap.TreeMap.opApply.html"},
{"containers.slist.SList" : "containers/slist.SList.html"},
{"containers.slist.SList.this" : "containers/slist.SList.this.html"},
{"containers.slist.SList.this" : "containers/slist.SList.this.html"},
{"containers.slist.SList.front" : "containers/slist.SList.front.html"},
{"containers.slist.SList.moveFront" : "containers/slist.SList.moveFront.html"},
{"containers.slist.SList.popFront" : "containers/slist.SList.popFront.html"},
{"containers.slist.SList.empty" : "containers/slist.SList.empty.html"},
{"containers.slist.SList.length" : "containers/slist.SList.length.html"},
{"containers.slist.SList.insert" : "containers/slist.SList.insert.html"},
{"containers.slist.SList.insertFront" : "containers/slist.SList.insertFront.html"},
{"containers.slist.SList.put" : "containers/slist.SList.put.html"},
{"containers.slist.SList.opOpAssign" : "containers/slist.SList.opOpAssign.html"},
{"containers.slist.SList.remove" : "containers/slist.SList.remove.html"},
{"containers.slist.SList.range" : "containers/slist.SList.range.html"},
{"containers.slist.SList.opSlice" : "containers/slist.SList.opSlice.html"},
{"containers.slist.SList.clear" : "containers/slist.SList.clear.html"},
{"containers.unrolledlist.UnrolledList" : "containers/unrolledlist.UnrolledList.html"},
{"containers.unrolledlist.UnrolledList.insertBack" : "containers/unrolledlist.UnrolledList.insertBack.html"},
{"containers.unrolledlist.UnrolledList.insertBack" : "containers/unrolledlist.UnrolledList.insertBack.html"},
{"containers.unrolledlist.UnrolledList.put" : "containers/unrolledlist.UnrolledList.put.html"},
{"containers.unrolledlist.UnrolledList.insert" : "containers/unrolledlist.UnrolledList.insert.html"},
{"containers.unrolledlist.UnrolledList.insertAnywhere" : "containers/unrolledlist.UnrolledList.insertAnywhere.html"},
{"containers.unrolledlist.UnrolledList.length" : "containers/unrolledlist.UnrolledList.length.html"},
{"containers.unrolledlist.UnrolledList.empty" : "containers/unrolledlist.UnrolledList.empty.html"},
{"containers.unrolledlist.UnrolledList.remove" : "containers/unrolledlist.UnrolledList.remove.html"},
{"containers.unrolledlist.UnrolledList.popFront" : "containers/unrolledlist.UnrolledList.popFront.html"},
{"containers.unrolledlist.UnrolledList.moveFront" : "containers/unrolledlist.UnrolledList.moveFront.html"},
{"containers.unrolledlist.UnrolledList.front" : "containers/unrolledlist.UnrolledList.front.html"},
{"containers.unrolledlist.UnrolledList.nodeCapacity" : "containers/unrolledlist.UnrolledList.nodeCapacity.html"},
{"containers.unrolledlist.UnrolledList.range" : "containers/unrolledlist.UnrolledList.range.html"},
{"containers.unrolledlist.UnrolledList.opSlice" : "containers/unrolledlist.UnrolledList.opSlice.html"},
{"containers.internal.hash.hashString" : "containers/internal/hash.hashString.html"},
{"containers.immutablehashset.ImmutableHashSet" : "containers/immutablehashset.ImmutableHashSet.html"},
{"containers.immutablehashset.ImmutableHashSet.this" : "containers/immutablehashset.ImmutableHashSet.this.html"},
{"containers.immutablehashset.ImmutableHashSet.opSlice" : "containers/immutablehashset.ImmutableHashSet.opSlice.html"},
{"containers.immutablehashset.ImmutableHashSet.contains" : "containers/immutablehashset.ImmutableHashSet.contains.html"},
{"containers.immutablehashset.ImmutableHashSet.length" : "containers/immutablehashset.ImmutableHashSet.length.html"},
{"containers.immutablehashset.ImmutableHashSet.empty" : "containers/immutablehashset.ImmutableHashSet.empty.html"},
{"containers.hashset.HashSet" : "containers/hashset.HashSet.html"},
{"containers.hashset.HashSet" : "containers/hashset.HashSet.html"},
{"containers.hashset.HashSet" : "containers/hashset.HashSet.html"},
{"containers.hashset.HashSet.this" : "containers/hashset.HashSet.this.html"},
{"containers.hashset.HashSet.clear" : "containers/hashset.HashSet.clear.html"},
{"containers.hashset.HashSet.remove" : "containers/hashset.HashSet.remove.html"},
{"containers.hashset.HashSet.contains" : "containers/hashset.HashSet.contains.html"},
{"containers.hashset.HashSet.opBinaryRight" : "containers/hashset.HashSet.opBinaryRight.html"},
{"containers.hashset.HashSet.insert" : "containers/hashset.HashSet.insert.html"},
{"containers.hashset.HashSet.put" : "containers/hashset.HashSet.put.html"},
{"containers.hashset.HashSet.empty" : "containers/hashset.HashSet.empty.html"},
{"containers.hashset.HashSet.length" : "containers/hashset.HashSet.length.html"},
{"containers.hashset.HashSet.range" : "containers/hashset.HashSet.range.html"},
{"containers.hashset.HashSet.opSlice" : "containers/hashset.HashSet.opSlice.html"},
{"containers.ttree.TTree" : "containers/ttree.TTree.html"},
{"containers.ttree.TTree.opOpAssign" : "containers/ttree.TTree.opOpAssign.html"},
{"containers.ttree.TTree.insert" : "containers/ttree.TTree.insert.html"},
{"containers.ttree.TTree.insert" : "containers/ttree.TTree.insert.html"},
{"containers.ttree.TTree.insert" : "containers/ttree.TTree.insert.html"},
{"containers.ttree.TTree.remove" : "containers/ttree.TTree.remove.html"},
{"containers.ttree.TTree.contains" : "containers/ttree.TTree.contains.html"},
{"containers.ttree.TTree.length" : "containers/ttree.TTree.length.html"},
{"containers.ttree.TTree.empty" : "containers/ttree.TTree.empty.html"},
{"containers.ttree.TTree.opSlice" : "containers/ttree.TTree.opSlice.html"},
{"containers.ttree.TTree.lowerBound" : "containers/ttree.TTree.lowerBound.html"},
{"containers.ttree.TTree.equalRange" : "containers/ttree.TTree.equalRange.html"},
{"containers.ttree.TTree.upperBound" : "containers/ttree.TTree.upperBound.html"},
{"containers.ttree.TTree.Range" : "containers/ttree.TTree.Range.html"},
{"containers.ttree.TTree.Range.front" : "containers/ttree.TTree.Range.front.html"},
{"containers.ttree.TTree.Range.empty" : "containers/ttree.TTree.Range.empty.html"},
{"containers.ttree.TTree.Range.popFront" : "containers/ttree.TTree.Range.popFront.html"},
{"containers.ttree.TTree.Range.save" : "containers/ttree.TTree.Range.save.html"},
{"containers.hashmap.HashMap" : "containers/hashmap.HashMap.html"},
{"containers.hashmap.HashMap.this" : "containers/hashmap.HashMap.this.html"},
{"containers.hashmap.HashMap.opIndex" : "containers/hashmap.HashMap.opIndex.html"},
{"containers.hashmap.HashMap.opIndexAssign" : "containers/hashmap.HashMap.opIndexAssign.html"},
{"containers.hashmap.HashMap.opBinaryRight" : "containers/hashmap.HashMap.opBinaryRight.html"},
{"containers.hashmap.HashMap.remove" : "containers/hashmap.HashMap.remove.html"},
{"containers.hashmap.HashMap.length" : "containers/hashmap.HashMap.length.html"},
{"containers.hashmap.HashMap.keys" : "containers/hashmap.HashMap.keys.html"},
{"containers.hashmap.HashMap.values" : "containers/hashmap.HashMap.values.html"},
{"containers.hashmap.HashMap.opApply" : "containers/hashmap.HashMap.opApply.html"},
{"containers.hashmap.HashMap.shouldRehash" : "containers/hashmap.HashMap.shouldRehash.html"},
{"containers.hashmap.HashMap.rehash" : "containers/hashmap.HashMap.rehash.html"},
{"containers.dynamicarray.DynamicArray" : "containers/dynamicarray.DynamicArray.html"},
{"containers.dynamicarray.DynamicArray.opSlice" : "containers/dynamicarray.DynamicArray.opSlice.html"},
{"containers.dynamicarray.DynamicArray.opSlice" : "containers/dynamicarray.DynamicArray.opSlice.html"},
{"containers.dynamicarray.DynamicArray.opIndex" : "containers/dynamicarray.DynamicArray.opIndex.html"},
{"containers.dynamicarray.DynamicArray.insert" : "containers/dynamicarray.DynamicArray.insert.html"},
{"containers.dynamicarray.DynamicArray.put" : "containers/dynamicarray.DynamicArray.put.html"},
{"containers.dynamicarray.DynamicArray.opIndexAssign" : "containers/dynamicarray.DynamicArray.opIndexAssign.html"},
{"containers.dynamicarray.DynamicArray.opSliceAssign" : "containers/dynamicarray.DynamicArray.opSliceAssign.html"},
{"containers.dynamicarray.DynamicArray.opSliceAssign" : "containers/dynamicarray.DynamicArray.opSliceAssign.html"},
{"containers.dynamicarray.DynamicArray.length" : "containers/dynamicarray.DynamicArray.length.html"},
{"memory.appender.Appender" : "memory/appender.Appender.html"},
{"memory.appender.Appender.this" : "memory/appender.Appender.this.html"},
{"memory.appender.Appender.opSlice" : "memory/appender.Appender.opSlice.html"},
{"memory.appender.Appender.append" : "memory/appender.Appender.append.html"},
{"memory.allocators.NodeAllocator" : "memory/allocators.NodeAllocator.html"},
{"memory.allocators.QuickAllocator" : "memory/allocators.QuickAllocator.html"},
{"memory.allocators.BlockAllocator" : "memory/allocators.BlockAllocator.html"},
{"memory.allocators.BlockAllocator.allocate" : "memory/allocators.BlockAllocator.allocate.html"},
{"memory.allocators.BlockAllocator.allocateNewNode" : "memory/allocators.BlockAllocator.allocateNewNode.html"},
{"memory.allocators.BlockAllocator.allocateInNode" : "memory/allocators.BlockAllocator.allocateInNode.html"},
{"memory.allocators.BlockAllocator.Node" : "memory/allocators.BlockAllocator.Node.html"},
{"memory.allocators.BlockAllocator.root" : "memory/allocators.BlockAllocator.root.html"},
{"memory.allocators.BlockAllocator.roundUpToMultipleOf" : "memory/allocators.BlockAllocator.roundUpToMultipleOf.html"},
];
function search(str) {
	var re = new RegExp(str.toLowerCase());
	var ret = {};
	for (var i = 0; i < items.length; i++) {
		var k = Object.keys(items[i])[0];
		if (re.test(k.toLowerCase()))
			ret[k] = items[i][k];
	}
	return ret;
}

function searchSubmit(value, event) {
	console.log("searchSubmit");
	var resultTable = document.getElementById("results");
	while (resultTable.firstChild)
		resultTable.removeChild(resultTable.firstChild);
	if (value === "" || event.keyCode == 27) {
		resultTable.style.display = "none";
		return;
	}
	resultTable.style.display = "block";
	var results = search(value);
	var keys = Object.keys(results);
	if (keys.length === 0) {
		var row = resultTable.insertRow();
		var td = document.createElement("td");
		var node = document.createTextNode("No results");
		td.appendChild(node);
		row.appendChild(td);
		return;
	}
	for (var i = 0; i < keys.length; i++) {
		var k = keys[i];
		var v = results[keys[i]];
		var link = document.createElement("a");
		link.href = v;
		link.textContent = k;
		var row = resultTable.insertRow();
		row.appendChild(link);
	}
}

function hideSearchResults(event) {
	if (event.keyCode != 27)
		return;
	var resultTable = document.getElementById("results");
	while (resultTable.firstChild)
		resultTable.removeChild(resultTable.firstChild);
	resultTable.style.display = "none";
}

