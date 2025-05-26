return {
    PATH = "skip",

    ui = {
        icons = {
            package_pending = " ",
            package_installed = " ",
            package_uninstalled = " ",
        },
    },

    ensure_installed = {
        "bash-language-server",
        "css-lsp",
        "dockerfile-language-server",
        "eslint-lsp",
        "html-lsp",
        "json-lsp",
        "lua-language-server",
        "markdownlint-cli2",
        "prettier",
        "pyright",
    },
    max_concurrent_installers = 10,
}
