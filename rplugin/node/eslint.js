
//eslint modules
var SourceCode = require("eslint").SourceCode;
var CLIEngine = require("eslint").CLIEngine;
var linter = require('eslint').linter;
var espree = require('espree');

var eslintCLI = new CLIEngine({});

//default config
var config = {
    ecmaFeatures: {}
};

function _debug() {
    debug.apply(null, arguments);
} 

function isModule(js) {
    var import_re = /^\s*import\s/m;
    var export_re = /^\s*export\s/m;
    return import_re.test(js) || export_re.test(js);
}

function getConfig(filename) {
    try {
        config = eslintCLI.getConfigForFile(filename);
    } catch (e) {
        _debug("error parsing eslintrc", e)
    }
}

function getLint(input_js) {
    
    var sourceType = isModule(input_js) ? 'module' : 'script';

    try {
    
        var ast = espree.parse(input_js, {
            range: true,
            loc: true,
            tolerant: true,
            tokens: true,
            comments: true,
            attachComment: true,
            ecmaVersion: 6,
            sourceType: sourceType,
            ecmaFeatures:  config.ecmaFeatures   
        });
    } catch (e) {
        _debug('failed to parse:', e);
        //return a fatal error
        return[{
            fatal: true,
            message: e.message,
            severity: 2,
            line: e.lineNumber,
            column: e.column
        }]
    }

    var sourceCode = new SourceCode(input_js, ast);
    var messages = linter.verify(sourceCode, config);
            _debug('MESSAGES:',  messages);

    return messages;
}

function getBufferText(nv) {

    //var start = (new Date()).getTime();
    nv.callFunction('GetBufferText', [], function (err, res) {

        var messages = [];

        if (err) _debug(err);

        messages = getLint(res);
        
        nv.callFunction('ShowEslintOutput', [JSON.stringify({messages: messages})], function (err, res) {
            if (err) _debug(err);
        });
    });

}

plugin.autocmdSync('BufRead', {
    pattern: '*.js',
    eval: 'expand("%:p")'
}, function (nvim, filepath) {
    getConfig(filepath);
    getBufferText(nvim);
});

plugin.autocmd('User', {
    pattern: 'eslint.lint'
}, getBufferText);

