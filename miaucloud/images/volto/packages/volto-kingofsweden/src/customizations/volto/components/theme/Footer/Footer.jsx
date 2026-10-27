import React from 'react';
import { Container, Segment } from 'semantic-ui-react';

const Footer = () => {
  return (
    <Segment
      role="contentinfo"
      vertical
      padded
      inverted
      color="grey"
      textAlign="center"
      id="footer"
      aria-label="Footer"
      tabIndex="-1"
    >
      <Container>
        <Segment basic inverted color="grey" className="discreet">
          <p>© {new Date().getFullYear()} King of Sweden.</p>
        </Segment>
      </Container>
    </Segment>
  );
};

export default Footer;
