data:extend({
    {
        name = "bluebuild-speed",
        type = "int-setting",
        localised_description = ({"", "How many ticks should pass between BlueBuild+ placing, demolishing or upgrading tiles.\nSet to 0 for super-fast updating."}),
        default_value = 12,
        minimum_value = 0,
        setting_type = "runtime-global",
        order = "1001"
    }
})
