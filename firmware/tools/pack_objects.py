# The staged character pack's sources sit outside src/ (.character-build),
# so PlatformIO builds them into one folder every env shares, while each
# env builds them with its own flags (its face, its board). An env would
# link the objects another env built last, so each build starts them afresh.
import os
import shutil

Import("env")  # noqa: F821 (PlatformIO's)

shutil.rmtree(os.path.join(env.subst("$PROJECT_BUILD_DIR"), ".character-build"), ignore_errors=True)  # noqa: F821
