#!/bin/bash
# Generates the Mali Bifrost madvise/MGLRU patch in the appropriate tree directory.
#
# This strips restrictive VM mapping flags from KBASE_MEM_TYPE_NATIVE allocations
# to allow libmali and libmali-vulkan to leverage madvise(MADV_DONTNEED) and
# Linux MGLRU aging/reclaim globally.
#
# Correctness notes:
#   - Only KBASE_MEM_TYPE_NATIVE is targeted. These are struct-page-backed GPU
#     allocations (shader stores, UBOs, VBOs, etc.) eligible for MGLRU aging.
#   - KBASE_MEM_TYPE_IMPORTED_UMM (dma-buf/scanout) is intentionally excluded:
#     those VMAs may back non-RAM memory (CMA, device memory) and require VM_IO
#     and VM_PFNMAP for correct pfn mapping behaviour.
#   - VM_MIXEDMAP is NOT set: native allocations are homogeneous struct-page
#     mappings. Setting VM_MIXEDMAP after clearing VM_PFNMAP is contradictory
#     and will confuse follow_page() and page migration paths.
#   - VM_NOHUGEPAGE is retained: CONFIG_TRANSPARENT_HUGEPAGE_MADVISE is active
#     and the ROCKNIX memory manager triggers vm.compact_memory. Pinning 4K
#     granularity here avoids spurious THP promotion races on GPU buffer faults.
#   - LRU_GEN_WALKS_MMU=y is confirmed in the RK3566 kernel config, so MGLRU
#     will track these pages via hardware pgtable walks once VM_IO is cleared.

PATCH_DIR="projects/ROCKNIX/devices/RK3566/patches/mali-bifrost"
PATCH_FILE="$PATCH_DIR/003-mali-bifrost-madvise-mglru.patch"

mkdir -p "$PATCH_DIR"

# Write the patch file using Python to guarantee tab characters are preserved
# exactly as literal bytes. Bash heredocs, printf, and terminal copy-paste
# buffers all risk silently mangling tabs in diff hunk bodies, which causes
# GNU patch to reject the file with "malformed patch".
#
# Hunk arithmetic (verified with patch --dry-run against a source stub):
#   Insertion point: after the blank line following __vm_flags_mod (~line 1242).
#   Context before:  3 lines (blank@1240, __vm_flags_mod@1241, blank@1242)
#   Added lines:     15 (11-line comment block + 4-line if block)
#   Context after:   3 lines (vma->vm_ops, vma->vm_private_data, blank)
#   @@ -1240,6 +1240,21 @@  (minus=3+3=6, plus=3+15+3=21)
python3 - "$PATCH_FILE" << 'PYEOF'
import sys

T = '\t'   # explicit tab - never mangled by Python string literals

lines = [
    "From: Joel Wirāmu Pauling <aenertia@aenertia.net>",
    "Date: Thu, 26 Feb 2026 20:00:00 +1300",
    "Subject: [PATCH] mali: bifrost: Enable madvise and MGLRU reclaim for native kbase mem",
    "",
    "Strip VM_IO and VM_PFNMAP from CPU VMAs backed by KBASE_MEM_TYPE_NATIVE",
    "allocations so that:",
    "",
    "  1. madvise(MADV_DONTNEED) works correctly from libmali/libmali-vulkan,",
    "     allowing userspace to hint purgeable GPU buffers back to the kernel.",
    "",
    "  2. Linux MGLRU (CONFIG_LRU_GEN + LRU_GEN_WALKS_MMU) can age and reclaim",
    "     these pages via hardware pgtable walks, improving memory pressure",
    "     handling on constrained RK3566 devices.",
    "",
    "VM_IO and VM_PFNMAP are intentionally preserved on KBASE_MEM_TYPE_IMPORTED_UMM",
    "(dma-buf/scanout) mappings, which may back non-RAM memory and require the",
    "original pfn-mapping semantics for correct operation.",
    "",
    "VM_MIXEDMAP is not applied: native allocations are homogeneous struct-page",
    "mappings and do not require mixed pfn/page handling. Setting it here would",
    "confuse follow_page() and page migration.",
    "",
    "VM_NOHUGEPAGE is added to prevent spurious THP promotion races. The RK3566",
    "kernel is built with CONFIG_TRANSPARENT_HUGEPAGE_MADVISE and the ROCKNIX",
    "memory manager triggers vm.compact_memory at runtime; without this flag,",
    "compaction could attempt to collapse 4K GPU buffer pages into a hugepage",
    "during a concurrent fault-in, causing blank screen hangs on the compositor.",
    "",
    "Kernel config confirmed: LRU_GEN=y, LRU_GEN_ENABLED=y, LRU_GEN_WALKS_MMU=y,",
    "TRANSPARENT_HUGEPAGE_MADVISE=y (Linux 6.18, aarch64, ROCKNIX RK3566).",
    "",
    "---",
    " product/kernel/drivers/gpu/arm/midgard/mali_kbase_mem_linux.c | 15 +++++++++++++++",
    " 1 file changed, 15 insertions(+)",
    "",
    "diff --git a/product/kernel/drivers/gpu/arm/midgard/mali_kbase_mem_linux.c b/product/kernel/drivers/gpu/arm/midgard/mali_kbase_mem_linux.c",
    "--- a/product/kernel/drivers/gpu/arm/midgard/mali_kbase_mem_linux.c",
    "+++ b/product/kernel/drivers/gpu/arm/midgard/mali_kbase_mem_linux.c",
    "@@ -1240,6 +1240,21 @@ static int kbase_cpu_mmap(struct kbase_context *kctx, struct kbase_va_region *re",
    # 3 context lines before insertion point
    " ",                                                                                         # blank
    " " + T + "__vm_flags_mod(vma, VM_DONTCOPY | VM_DONTDUMP | VM_DONTEXPAND | VM_IO, 0);",
    " ",                                                                                         # blank
    # 15 added lines: 11-line comment + 4-line if block
    "+" + T + "/*",
    "+" + T + " * ROCKNIX/MGLRU: For native struct-page-backed GPU allocations, strip",
    "+" + T + " * VM_IO and VM_PFNMAP so that madvise(MADV_DONTNEED) is honoured by the",
    "+" + T + " * kernel and MGLRU (LRU_GEN_WALKS_MMU) can age and reclaim these pages.",
    "+" + T + " *",
    "+" + T + " * KBASE_MEM_TYPE_IMPORTED_UMM (dma-buf/scanout) is deliberately excluded:",
    "+" + T + " * those mappings may cover non-RAM pfns and must retain VM_IO/VM_PFNMAP.",
    "+" + T + " *",
    "+" + T + " * VM_NOHUGEPAGE guards against THP promotion races during vm.compact_memory",
    "+" + T + " * triggered by the ROCKNIX memory manager (TRANSPARENT_HUGEPAGE_MADVISE).",
    "+" + T + " */",
    "+" + T + "if (reg->cpu_alloc->type == KBASE_MEM_TYPE_NATIVE) {",
    "+" + T + T + "vm_flags_clear(vma, VM_IO | VM_PFNMAP);",
    "+" + T + T + "vm_flags_set(vma, VM_NOHUGEPAGE);",
    "+" + T + "}",
    # 3 context lines after insertion point
    " " + T + "vma->vm_ops = &kbase_vm_ops;",
    " " + T + "vma->vm_private_data = map;",
    " ",
]

with open(sys.argv[1], 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF

echo "Successfully created $PATCH_FILE"
