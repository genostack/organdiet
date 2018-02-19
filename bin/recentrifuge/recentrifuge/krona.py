"""
Classes and functions directly related with Krona.

"""
# pylint: disable=not-an-iterable
import csv
import html
import os
import subprocess
from typing import List, Dict, NewType, Any, Optional
import xml.etree.ElementTree as ETree
from xml.dom import minidom

from recentrifuge.config import JSLIB, HTML_SUFFIX, Filename, Sample, Scoring

# from recentrifuge.config import HTML_SUFFIX

# Type annotations
# pylint: disable=invalid-name
Attrib = NewType('Attrib', str)  # Refers to Krona attributes not XML ones
Elm = ETree.Element
# pylint: enable=invalid-name

# Predefined constants
COUNT = Attrib('count')
UNASSIGNED = Attrib('unassigned')
TID = Attrib('tid')
RANK = Attrib('rank')
SCORE = Attrib('score')

# Define encoding dialect for TSV files expected by Krona
csv.register_dialect('krona', 'unix', delimiter='\t', quoting=csv.QUOTE_NONE)


class KronaTree(ETree.ElementTree):
    """Kronified ElementTree."""

    @staticmethod
    def sub(parent: Elm,
            tag: str,
            attrib: Dict[str, str] = None,
            text: str = None,
            ) -> Elm:
        """Wrapper around ETree.SubElement."""
        if attrib:
            subelement = ETree.SubElement(parent, tag, attrib)
        else:
            subelement = ETree.SubElement(parent, tag)
        if text is not None:
            subelement.text = text
        return subelement

    def node(self,
             parent: Elm,
             name: str,
             values: Dict[Attrib, Any],
             ) -> Elm:
        """Wrapper for creating a meaningful Krona node.

        For details, please consult:
        https://github.com/marbl/Krona/wiki/Krona-2.0-XML-Specification
        """
        subnode = self.sub(parent, 'node',
                           {'name': name,
                            'href': f'https://www.google.es/search?q={name}'})
        count_node = self.sub(subnode, COUNT)
        counts: Dict[Sample, str] = {sample: values[COUNT][sample]
                                     for sample in self.samples}
        for sample in self.samples:
            counts_value: Optional[str] = counts[sample]
            if int(counts_value) == 0:  # Save space (warning! empty tags)
                counts_value = None  # Empty instead of 0 inside <val></val>
            self.sub(count_node, 'val', None, counts_value)
        if values.get(UNASSIGNED) and any(values[UNASSIGNED].values()):
            # Avoid including and save space if all the unassigned values are 0
            unassigned_node = self.sub(subnode, UNASSIGNED)
            unassigned: Dict[Sample, str] = {sample: values[UNASSIGNED][sample]
                                             for sample in self.samples}
            for sample in self.samples:
                unassigned_value: Optional[str] = unassigned[sample]
                if int(unassigned_value) == 0:  # Save space (empty tags!)
                    unassigned_value = None  # Empty and not 0 after <val>
                self.sub(unassigned_node, 'val', None, unassigned_value)
        if values.get(TID):
            tid_node = self.sub(subnode, TID)
            self.sub(tid_node, 'val',
                     {'href': values[TID]},
                     values[TID])
        if values.get(RANK):
            rank_node = self.sub(subnode, RANK)
            self.sub(rank_node, 'val', None, values[RANK])
        if values.get(SCORE):
            score_node = self.sub(subnode, SCORE)
            scores: Dict[Sample, str] = {sample: values[SCORE][sample]
                                         for sample in self.samples}
            for sample in self.samples:
                self.sub(score_node, 'val', None, scores[sample])
        return subnode

    @staticmethod
    def to_pretty_string(element: Elm):
        """Return a pretty-printed XML string for the Element."""
        raw_string = ETree.tostring(element,
                                    encoding='unicode',
                                    method='xml',
                                    short_empty_elements=False,
                                    )
        re_parsed = minidom.parseString(raw_string)
        pretty = re_parsed.toprettyxml(indent='  ')
        pretty = html.unescape(pretty)
        return pretty.split('\n', 1)[-1]  # Remove the XML 1.0 tag

    def __init__(self,
                 samples: List[Sample],
                 num_raw_samples: int = None,
                 min_score: float = 0.0,
                 max_score: float = 1.0,
                 scoring: Scoring = Scoring.SHEL,
                 ) -> None:
        """
        Args:
            samples: List of samples in the set
            num_raw_samples: Number of raw samples (not from cross-analysis)
            min_score: minimum expected score
            max_score: maximum expected score
        """
        # Type declaration
        self.krona: Elm
        self.krona_tree: ETree.ElementTree
        self.attributes: Elm
        self.samples: List[Sample]
        self.datasets: Elm

        # Set root of KronaTree
        self.krona = ETree.Element('krona',
                                   attrib={'collapse': 'true', 'key': 'true'})

        # Set attributes
        self.attributes = ETree.SubElement(self.krona, 'attributes',
                                           {'magnitude': 'count'})
        self.sub(self.attributes, 'attribute',
                 {'display': 'Count', 'dataAll': 'members'},
                 'count')
        self.sub(self.attributes, 'attribute',
                 {'display': 'Unassigned', 'dataNode': 'members'},
                 'unassigned')
        self.sub(self.attributes, 'attribute',
                 {'display': 'TaxID', 'mono': 'true',
                  'hrefBase':
                      'https://www.ncbi.nlm.nih.gov/Taxonomy/'
                      'Browser/wwwtax.cgi?mode=Info&id='},
                 'tid')
        self.sub(self.attributes, 'attribute',
                 {'display': 'Rank', 'mono': 'true'},
                 'rank')
        display: str
        if scoring is Scoring.SHEL:
            display = 'Confidence (avg)'
        elif scoring is Scoring.LENGTH:
            display = 'Read length (avg)'
        elif scoring is Scoring.LOGLENGTH:
            display = 'Read length (avg, log10)'
        elif scoring is Scoring.NORMA:
            display = 'Confidence/Length (%)'
        elif scoring is Scoring.LMAT:
            display = 'LMAT score (avg)'
        else:
            raise Exception(
                f'\n\033[91mERROR!\033[0m Unknown Scoring "{scoring}"')
        self.sub(self.attributes, 'attribute',
                 {'display': display},
                 'score')

        # Set datasets
        self.samples = samples
        self.datasets = ETree.SubElement(self.krona, 'datasets',
                                         {'rawSamples': f'{num_raw_samples}'})
        for sample in self.samples:
            self.sub(self.datasets, 'dataset', {}, sample)

        # Set color
        self.color = self.sub(self.krona, 'color',
                              {'attribute': 'score',
                               'hueStart': '0',
                               'hueEnd': '300',
                               'valueStart': f'{min_score:.1f}',
                               'valueEnd': f'{max_score:.1f}',
                               'default': 'true'},
                              ' ')  # Krona: Avoid empty-element tag

        super(KronaTree, self).__init__(self.krona)

    def __repr__(self):
        return self.to_pretty_string(self.krona)

    def tofile(self,
               filename: Filename,
               pretty: bool = False,
               ) -> None:
        """
        Write KronaTree in 'plain' or 'pretty' XML.

        Args:
            filename: the name of the XML output file.
            pretty: this parameter controls the layout of the XML code
                so that it is human readable for True (use for debug
                only because it uses a lot more of space and also has
                empty tags which are currently not supported by Krona)
                and machine readable for False (default, saves space).

        Returns: None

        """
        with open(filename, 'w') as xml_file:
            if pretty:
                xml_file.write(self.to_pretty_string(self.krona))
            else:
                self.write(xml_file,
                           encoding='unicode',
                           xml_declaration=False,
                           method='xml',
                           short_empty_elements=False,
                           )

    def tohtml(self,
               filename: Filename,
               pretty: bool = False,
               ) -> None:
        """
        Write Krona HTML.

        Args:
            filename: the name of the HTML output file.
            pretty: this parameter controls the layout of the XML code
                so that it is human readable for True (use for debug
                only because it uses a lot more of space and also has
                empty tags which are currently not supported by Krona)
                and machine readable for False (default, saves space).

        Returns: None

        """
        # Read aux files
        path = os.path.dirname(os.path.realpath(__file__))
        with open(path + '/img/hidden.uri', 'r') as file:
            hidden_image = file.read()
        with open(path + '/img/loading.uri', 'r') as file:
            loading_image = file.read()
        with open(path + '/img/favicon.uri', 'r') as file:
            favicon = file.read()
        with open(path + '/img/logo-med.uri', 'r') as file:
            logo = file.read()
        with open(f'{path}/{JSLIB}', 'r') as file:
            script = file.read()

        # Set root of HTML doc
        html_root = ETree.Element('html', attrib={'xmlns':
                                                      'http://www.w3.org/1999/xhtml',
                                                  'xml:lang': 'en',
                                                  'lang': 'en'})
        # Prepare HTML file
        head = self.sub(html_root, 'head')
        self.sub(head, 'meta', {'charset': 'utf-8'})
        self.sub(head, 'link', {'rel': 'shortcut icon',
                                'href': favicon})
        self.sub(head, 'link', {'rel': 'stylesheet',
                                'href': 'https://fonts.googleapis.com/css?family=Ubuntu'})
        self.sub(head, 'script', {'id': 'notfound'},
                 'window.onload=function(){document.body.innerHTML=""}')
        self.sub(head, 'script',
                 {'language': 'javascript', 'type': 'text/javascript'},
                 script)  # Include javascript
        body = self.sub(html_root, 'body')
        self.sub(body, 'img', {'id': 'hiddenImage',
                               'src': hidden_image,
                               'style': 'display:none'})
        self.sub(body, 'img', {'id': 'loadingImage',
                               'src': loading_image,
                               'style': 'display:none'})
        self.sub(body, 'img', {'id': 'logo',
                               'src': logo,
                               'style': 'display:none'})
        self.sub(body, 'noscript', None,
                 'Javascript must be enabled to view this page.')

        div = self.sub(body, 'div', {'style': 'display:none'})
        div.append(self.krona)  # Include specific XML from samples
        # Write the HTML file
        with open(filename, 'w') as html_file:
            html_file.write(
                '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">\n')  # pylint: disable=line-too-long
            if pretty:
                html_file.write(self.to_pretty_string(html_root))
            else:
                html_file.write(ETree.tostring(html_root,
                                               encoding='unicode',
                                               method='html',
                                               short_empty_elements=False,
                                               )
                                )


def krona_from_xml(xmlfile: Filename,
                   htmlfile: Filename = Filename('Output' + HTML_SUFFIX),
                   ):
    """Generate the Krona html file calling ktImportXML."""
    subprc = ["ktImportXML"]
    subprc.append(xmlfile)
    subprc.extend(["-o", htmlfile])
    try:
        subprocess.run(subprc, check=True)
    except subprocess.CalledProcessError:
        print('\n\033[91mERROR!\033[0m ktImportXML: ' +
              'returned a non-zero exit status (Krona plot built failed)')
