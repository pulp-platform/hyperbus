Padrick advanced flow. Next step is to generate the internal
Mako templates used to generate the various export files. In order for the
customize option to have any effect, you need to invoke the generate
commands with the additional -s flag: e.g.: padrick generate -s
padrick_gen_settings.yml rtl my_padframe.yml

```bash
padrick generate template-customization -o templates
```

The template files should be modified to allow the rendered file to start with a proper copyright/license header
Finally the files can be generated using the command below:

```bash
padrick generate -s templates/padrick_generator_settings.yml rtl -o ../. config_top.yml
```

TO generate a CSV including the list of pads:


```bash
padrick generate padlist -o ../. config_top.yml
```