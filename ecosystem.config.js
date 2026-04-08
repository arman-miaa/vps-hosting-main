// for nextjs project

module.exports = {
  apps: [
    {
      name: "project-client",
      script: "node_modules/next/dist/bin/next",
      args: "start",
      env: {
        NODE_ENV: "production",
        PORT: 3001
      },
    },
  ],
};

// for modular nodejs project

module.exports = {
    apps: [
        {
            name: 'project-server',
            script: './dist/server.js',
            args: 'start',
            env: {
                NODE_ENV: 'production',
            },
        },
    ],
};