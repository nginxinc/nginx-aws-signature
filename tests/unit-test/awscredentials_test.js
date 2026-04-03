#!env njs

/*
 *  Copyright 2023 F5, Inc.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import awscred from "/etc/nginx/serverless/awscredentials.js";
import fs from "fs";

globalThis.ngx = {};


function testReadCredentialsWithAccessSecretKeyAndSessionTokenSet() {
    printHeader('testReadCredentialsWithAccessSecretKeyAndSessionTokenSet');
    let r = {};
    process.env['AWS_ACCESS_KEY_ID'] = 'SOME_ACCESS_KEY';
    process.env['AWS_SECRET_ACCESS_KEY'] = 'SOME_SECRET_KEY';
    if ('AWS_SESSION_TOKEN' in process.env) {
        process.env['AWS_SESSION_TOKEN'] = 'SOME_SESSION_TOKEN';
    }

    try {
        var credentials = awscred.readCredentials(r);
        if (credentials.accessKeyId !== process.env['AWS_ACCESS_KEY_ID']) {
            throw 'static credentials do not match returned value [accessKeyId]';
        }
        if (credentials.secretAccessKey !== process.env['AWS_SECRET_ACCESS_KEY']) {
            throw 'static credentials do not match returned value [secretAccessKey]';
        }
        if ('AWS_SESSION_TOKEN' in process.env) {
            if (credentials.sessionToken !== process.env['AWS_SESSION_TOKEN']) {
                throw 'static credentials do not match returned value [sessionToken]';
            }
        } else {
            if (credentials.sessionToken !== null) {
                throw 'static credentials do not match returned value [sessionToken]';
            }
        }
        if (credentials.expiration !== null) {
            throw 'static credentials do not match returned value [expiration]';
        }

    } finally {
        delete process.env.AWS_ACCESS_KEY_ID;
        delete process.env.AWS_SECRET_ACCESS_KEY;
        if ('AWS_SESSION_TOKEN' in process.env) {
            delete process.env.AWS_SESSION_TOKEN;
        }
    }
}

async function testEcsCredentialRetrieval() {
    printHeader('testEcsCredentialRetrieval');
    if ('AWS_ACCESS_KEY_ID' in process.env) {
        delete process.env['AWS_ACCESS_KEY_ID'];
    }
    process.env['AWS_CONTAINER_CREDENTIALS_RELATIVE_URI'] = '/example';
    globalThis.ngx.fetch = function (url) {
        console.log(' fetching mock credentials');
        globalThis.recordedUrl = url;

        return Promise.resolve({
            ok: true,
            json: function () {
                return Promise.resolve({
                    AccessKeyId: 'AN_ACCESS_KEY_ID',
                    Expiration: '2017-05-17T15:09:54Z',
                    RoleArn: 'TASK_ROLE_ARN',
                    SecretAccessKey: 'A_SECRET_ACCESS_KEY',
                    Token: 'A_SECURITY_TOKEN',
                });
            }
        });
    };
    var r = {
        "headersOut" : {
            "Accept-Ranges": "bytes",
            "Content-Length": 42,
            "Content-Security-Policy": "block-all-mixed-content",
            "Content-Type": "text/plain",
            "X-Amz-Bucket-Region": "us-east-1",
            "X-Amz-Request-Id": "166539E18A46500A",
            "X-Xss-Protection": "1; mode=block"
        },
        log: function(msg) {
            console.log(msg);
        },
        return: function(code) {
            if (code !== 200) {
                throw 'Expected 200 status code, got: ' + code;
            }
        },
    };

    await awscred.fetchCredentials(r);

    if (globalThis.recordedUrl !== 'http://169.254.170.2/example') {
        throw `No or wrong ECS credentials fetch URL recorded: ${globalThis.recordedUrl}`;
    }
}

async function testEc2CredentialRetrieval() {
    printHeader('testEc2CredentialRetrieval');
    if ('AWS_ACCESS_KEY_ID' in process.env) {
        delete process.env['AWS_ACCESS_KEY_ID'];
    }
    if ('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI' in process.env) {
        delete process.env['AWS_CONTAINER_CREDENTIALS_RELATIVE_URI'];    
    }
    globalThis.ngx.fetch = function (url, options) {
        if (url === 'http://169.254.169.254/latest/api/token' && options && options.method === 'PUT') {
            return Promise.resolve({
                ok: true,
                text: function () {
                    return Promise.resolve('A_TOKEN');
                },
            });
        } else if (url === 'http://169.254.169.254/latest/meta-data/iam/security-credentials/') {
            if (options && options.headers && options.headers['x-aws-ec2-metadata-token'] === 'A_TOKEN') {
                return Promise.resolve({
                    ok: true,
                    text: function () {
                        return Promise.resolve('A_ROLE_NAME');
                    },
                });
            } else {
                throw 'Invalid token passed: ' + options.headers['x-aws-ec2-metadata-token'];
            }
        }  else if (url === 'http://169.254.169.254/latest/meta-data/iam/security-credentials/A_ROLE_NAME') {
            if (options && options.headers && options.headers['x-aws-ec2-metadata-token'] === 'A_TOKEN') {
                return Promise.resolve({
                    ok: true,
                    json: function () {
                        globalThis.credentialsIssued = true;
                        return Promise.resolve({
                            AccessKeyId: 'AN_ACCESS_KEY_ID',
                            Expiration: '2017-05-17T15:09:54Z',
                            RoleArn: 'TASK_ROLE_ARN',
                            SecretAccessKey: 'A_SECRET_ACCESS_KEY',
                            Token: 'A_SECURITY_TOKEN',
                        });
                    },
                });
            } else {
                throw 'Invalid token passed: ' + options.headers['x-aws-ec2-metadata-token'];
            }
        } else {
            throw 'Invalid request URL: ' + url;
        }
    };
    var r = {
        "headersOut" : {
            "Accept-Ranges": "bytes",
            "Content-Length": 42,
            "Content-Security-Policy": "block-all-mixed-content",
            "Content-Type": "text/plain",
            "X-Amz-Bucket-Region": "us-east-1",
            "X-Amz-Request-Id": "166539E18A46500A",
            "X-Xss-Protection": "1; mode=block"
        },
        log: function(msg) {
            console.log(msg);
        },
        return: function(code) {
            if (code !== 200) {
                throw 'Expected 200 status code, got: ' + code;
            }
        },
    };

    await awscred.fetchCredentials(r);

    if (!globalThis.credentialsIssued) {
        throw 'Did not reach the point where EC2 credentials were issues.';
    }
}

async function test() {
    await testEc2CredentialRetrieval();
    await testEcsCredentialRetrieval();
    testReadCredentialsWithAccessSecretKeyAndSessionTokenSet();
}

function printHeader(testName) {
    console.log(`\n## ${testName}`);
}

test();
console.log('Finished unit tests for awscredentials.js');
