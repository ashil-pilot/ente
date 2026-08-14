import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";

void main() {
  test(
    "eligible final photo enters the collage as the final progress step",
    () {
      expect(
        memoryProgressTotalSteps(memoryItemCount: 7, includeCollage: true),
        8,
      );
      expect(
        memoryViewerForwardAction(
          currentIndex: 6,
          itemCount: 7,
          collageEligible: true,
          showingCollage: false,
          hasNextMemory: true,
        ),
        MemoryViewerForwardAction.enterCollage,
      );
    },
  );

  test("collage navigates back to the final photo and onward to memory", () {
    expect(
      memoryViewerBackAction(
        currentIndex: 6,
        itemCount: 7,
        showingCollage: true,
        hasPreviousMemory: true,
      ),
      MemoryViewerBackAction.leaveCollage,
    );
    expect(
      memoryViewerForwardAction(
        currentIndex: 6,
        itemCount: 7,
        collageEligible: true,
        showingCollage: true,
        hasNextMemory: true,
      ),
      MemoryViewerForwardAction.nextMemory,
    );
    expect(
      memoryViewerForwardAction(
        currentIndex: 6,
        itemCount: 7,
        collageEligible: true,
        showingCollage: true,
        hasNextMemory: false,
      ),
      MemoryViewerForwardAction.dismissViewer,
    );
  });

  test("ineligible final photo skips the collage", () {
    expect(
      memoryProgressTotalSteps(memoryItemCount: 6, includeCollage: false),
      6,
    );
    expect(
      memoryViewerForwardAction(
        currentIndex: 5,
        itemCount: 6,
        collageEligible: false,
        showingCollage: false,
        hasNextMemory: true,
      ),
      MemoryViewerForwardAction.nextMemory,
    );
    expect(
      memoryViewerForwardAction(
        currentIndex: 5,
        itemCount: 6,
        collageEligible: false,
        showingCollage: false,
        hasNextMemory: false,
      ),
      MemoryViewerForwardAction.stay,
    );
  });

  test("regular memory navigation remains unchanged", () {
    expect(
      memoryViewerForwardAction(
        currentIndex: 2,
        itemCount: 7,
        collageEligible: true,
        showingCollage: false,
        hasNextMemory: false,
      ),
      MemoryViewerForwardAction.nextItem,
    );
    expect(
      memoryViewerBackAction(
        currentIndex: 2,
        itemCount: 7,
        showingCollage: false,
        hasPreviousMemory: false,
      ),
      MemoryViewerBackAction.previousItem,
    );
    expect(
      memoryViewerBackAction(
        currentIndex: 0,
        itemCount: 7,
        showingCollage: false,
        hasPreviousMemory: true,
      ),
      MemoryViewerBackAction.previousMemory,
    );
  });
}
