# Solutions

Each Dataverse solution lives in its own folder, unpacked with SolutionPackager:

```
solutions/
  <SolutionUniqueName>/
    src/
      Other/Solution.xml
      Other/Customizations.xml
      ...component folders...
```

The folder name must match the solution's `UniqueName` in `Other/Solution.xml`;
the workflows use it to name artifacts and to find deployment settings.

`CoreCustomizations` is a **sample**. It only contains one environment variable
and one connection reference so that the build, solution checker and deployment
settings steps have something real to work with. Replace it with your own export
by running the *Export solution* workflow against your DEV environment.

Do not edit files under `src/` by hand except for trivial fixes. The next export
overwrites the folder, so the source of truth is DEV until the change is merged.
