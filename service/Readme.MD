The multi-stage build is thin. With no dependencies, the builder stage only creates an empty virtualenv. It’s structured so that adding a package to requirements.txt just works.

