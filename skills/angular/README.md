# Angular Skills

The Angular skills are designed to help coding agents create applications aligned with the latest versions of Angular, best practices, new features and manage Angular applications effectively. These skills provide architectural guidance, generate idiomatic Angular code, and help scaffold new projects using modern best practices.

## Available Skills

- **`angular-developer`**: Generates Angular code and provides architectural guidance. Useful for creating components, services, or obtaining best practices on reactivity (signals, linkedSignal, resource), forms, dependency injection, routing, SSR, accessibility (ARIA), animations, styling, testing, or CLI tooling.
- **`angular-new-app`**: Creates a new Angular app using the Angular CLI. Provides important guidelines for effectively setting up and structuring a modern Angular application.

## Using Agent Skills

Agent Skills are designed to be used with agentic coding tools like [Gemini CLI](https://geminicli.com/docs/cli/skills/), [Antigravity](https://antigravity.google/docs/skills) and more. Activating a skill loads the specific instructions and resources needed for that task.

To use these skills in your own environment you may follow the instructions for your specific tool or use a community tool like [skills.sh](https://skills.sh/).

```bash
npx --yes skills@1.5.21 add https://github.com/angular/skills/tree/22.1.0+sha-eb10e93 --yes
```

The ai-forge installer reads the equivalent executable and argument list from
`install.args`, asks for confirmation, and invokes it without shell evaluation.
Update both the CLI version and Angular skills commit deliberately.
