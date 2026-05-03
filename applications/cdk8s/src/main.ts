import { App, Chart, ApiObject } from 'cdk8s';
import { Construct } from 'constructs';

class HelloChart extends Chart {
  constructor(scope: Construct, id: string) {
    super(scope, id);

    new ApiObject(this, 'hello-namespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'hello-cdk8s',
      },
    });
  }
}

const app = new App({
  outdir: process.env.CDK8S_OUTDIR ?? 'dist',
});

new HelloChart(app, 'hello');

app.synth();
