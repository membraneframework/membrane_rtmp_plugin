[
  inputs: [
    "{lib,test,config,examples}/**/*.{ex,exs}",
    "c_src/**/*.spec.exs",
    ".formatter.exs",
    "*.exs"
  ],
  import_deps: [:membrane_core, :unifex]
]
