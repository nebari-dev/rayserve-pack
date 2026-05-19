// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`). There are various equivalent ways to declare
// your Docusaurus config — see https://docusaurus.io/docs/api/docusaurus-config

const {themes: prismThemes} = require('prism-react-renderer');
const lightCodeTheme = prismThemes.github;
const darkCodeTheme = prismThemes.dracula;

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Nebari Ray Serve Pack',
  tagline: 'Deploy Ray Serve on Nebari',
  favicon: 'img/favicon.ico',

  // Set the production url of the site.
  url: 'https://nebari-dev.github.io',
  // Base URL pathname (for GitHub Pages, e.g. /<repo-name>/).
  baseUrl: '/nebari-rayserve-pack/',

  // GitHub Pages deployment config (only used by `npm run deploy`).
  organizationName: 'nebari-dev',
  projectName: 'nebari-rayserve-pack',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  // Mermaid support for the architecture diagram in using-ray-serve.md
  markdown: {
    mermaid: true,
  },
  themes: ['@docusaurus/theme-mermaid'],

  // Client-side search index, no Algolia account required. Matches the
  // search backend used by nebari-dev/nebari-docs. The index is only
  // generated during `npm run build`; in dev mode the search box renders
  // but returns no results until you run the build.
  plugins: [
    [
      require.resolve('docusaurus-lunr-search'),
      {
        languages: ['en'],
      },
    ],
  ],

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          // Markdown content lives in ./docs/ (the Docusaurus default).
          // Mirrors the nebari-docs layout where the repo's docs/ directory
          // is the Docusaurus root and docs/docs/ holds the prose.
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          sidebarCollapsible: true,
          showLastUpdateTime: true,
          editUrl:
            'https://github.com/nebari-dev/nebari-rayserve-pack/edit/main/docs/docs/',
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Show the navbar light/dark toggle and respect the visitor's OS
      // preference on first load.
      colorMode: {
        defaultMode: 'light',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      docs: {
        sidebar: {
          hideable: true,
          autoCollapseCategories: true,
        },
      },
      navbar: {
        title: 'Nebari Ray Serve Pack',
        logo: {
          alt: 'Nebari logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            href: 'https://github.com/nebari-dev/nebari-rayserve-pack',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              {label: 'Get started', to: '/get-started/'},
              {label: 'How-to guides', to: '/how-tos/'},
              {label: 'Reference', to: '/references/'},
            ],
          },
          {
            title: 'Source',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/nebari-dev/nebari-rayserve-pack',
              },
              {
                label: 'Nebari',
                href: 'https://nebari.dev',
              },
            ],
          },
          {
            title: 'Ray',
            items: [
              {
                label: 'Ray Serve docs',
                href: 'https://docs.ray.io/en/latest/serve/index.html',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Nebari contributors.`,
      },
      prism: {
        theme: lightCodeTheme,
        darkTheme: darkCodeTheme,
        additionalLanguages: ['bash', 'yaml', 'toml', 'python'],
      },
    }),
};

module.exports = config;
